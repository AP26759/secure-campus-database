#!/usr/bin/env bash
set -euo pipefail

DB="campus_access"

# Run SQL as postgres and return a single plain value (no formatting)
run() {
  sudo -u postgres psql -X -d "$DB" -Atc "$1"
}

section() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

pass() { echo "PASS - $1"; }
fail() { echo "FAIL - $1"; exit 1; }

section "0) Setup + data checks"

# Database exists
if ! sudo -u postgres psql -Atc "SELECT 1 FROM pg_database WHERE datname='${DB}'" | grep -q 1; then
  fail "Database '${DB}' not found (run ./setup.sh first)"
fi
pass "Database exists"

# Schemas exist
schemas=$(run "SELECT COUNT(*) FROM pg_namespace WHERE nspname IN ('identity','ops','finance','config','audit','api');")
[[ "$schemas" -ge 6 ]] && pass "Schemas exist" || fail "Missing schemas"

# Core tables exist
for t in identity.users ops.buildings ops.access_events finance.payments audit.audit_log; do
  ok=$(run "SELECT to_regclass('$t') IS NOT NULL;")
  [[ "$ok" == "t" ]] && pass "Table exists: $t" || fail "Missing table: $t"
done

# API views exist
for v in api.v_building_catalogue api.v_finance_payments_overview api.v_audit_summary; do
  ok=$(run "SELECT to_regclass('$v') IS NOT NULL;")
  [[ "$ok" == "t" ]] && pass "View exists: $v" || fail "Missing view: $v"
done

# API function exists
okfn=$(run "SELECT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api' AND p.proname='request_access');")
[[ "$okfn" == "t" ]] && pass "API functions exist (request_access found)" || fail "API functions missing"

# Sample data exists
users=$(run "SELECT COUNT(*) FROM identity.users;")
buildings=$(run "SELECT COUNT(*) FROM ops.buildings;")
[[ "$users" -ge 5 ]] && pass "Sample users loaded (>=5)" || fail "Sample users not loaded"
[[ "$buildings" -ge 3 ]] && pass "Sample buildings loaded (>=3)" || fail "Sample buildings not loaded"

# Resolve IDs based on your INSERTs
alice=$(run "SELECT user_id FROM identity.users WHERE username='alice';")
bob=$(run "SELECT user_id FROM identity.users WHERE username='bob';")
carol=$(run "SELECT user_id FROM identity.users WHERE username='carol';")
dave=$(run "SELECT user_id FROM identity.users WHERE username='dave';")

lib=$(run "SELECT building_id FROM ops.buildings WHERE building_name='Library';")
lab=$(run "SELECT building_id FROM ops.buildings WHERE building_name='Engineering Lab';")
dc=$(run "SELECT building_id FROM ops.buildings WHERE building_name='Data Centre';")

[[ -n "$alice" && -n "$bob" && -n "$carol" && -n "$dave" ]] || fail "Missing one of alice/bob/carol/dave"
[[ -n "$lib" && -n "$lab" && -n "$dc" ]] || fail "Missing one of Library/Engineering Lab/Data Centre"
pass "Resolved sample IDs"

# Role mappings exist (based on your user_roles inserts)
sec_role=$(run "
SELECT EXISTS(
  SELECT 1
  FROM identity.user_roles ur
  JOIN identity.roles r ON r.role_id=ur.role_id
  WHERE ur.user_id=$bob AND r.role_name='security_officer'
);")
[[ "$sec_role" == "t" ]] && pass "Bob mapped to security_officer (table role model)" || fail "Bob is not mapped to security_officer"

fin_role=$(run "
SELECT EXISTS(
  SELECT 1
  FROM identity.user_roles ur
  JOIN identity.roles r ON r.role_id=ur.role_id
  WHERE ur.user_id=$carol AND r.role_name='finance_officer'
);")
[[ "$fin_role" == "t" ]] && pass "Carol mapped to finance_officer (table role model)" || fail "Carol is not mapped to finance_officer"

# Permission already seeded: Alice -> Engineering Lab
perm_exists=$(run "SELECT EXISTS(SELECT 1 FROM ops.building_permissions WHERE user_id=$alice AND building_id=$lab);")
[[ "$perm_exists" == "t" ]] && pass "Seed permission exists: Alice -> Engineering Lab" || fail "Seed permission missing for Alice -> Engineering Lab"

section "1) Functional tests (design works correctly)"

echo "Test 1.1: Alice -> Library (expected granted)"
res=$(run "SELECT status FROM api.request_access($alice, $lib, NULL, '127.0.0.1'::inet);")
echo "Result: $res"
[[ "$res" == "granted" ]] && pass "Access granted correctly" || fail "Expected granted"

echo
echo "Test 1.2: Alice -> Data Centre (expected denied)"
res=$(run "SELECT status FROM api.request_access($alice, $dc, NULL, '127.0.0.1'::inet);")
echo "Result: $res"
[[ "$res" == "denied" ]] && pass "Access denied correctly" || fail "Expected denied"

echo
echo "Test 1.3: Alice -> Engineering Lab (expected granted via seeded permission)"
res=$(run "SELECT status FROM api.request_access($alice, $lab, NULL, '127.0.0.1'::inet);")
echo "Result: $res"
[[ "$res" == "granted" ]] && pass "Seeded permission works correctly" || fail "Expected granted"

section "2) Task 1 issues fixed (types + constraints + FKs)"

echo "Test 2.1: access_events.event_time is TIMESTAMPTZ (not text)"
dtype=$(run "SELECT data_type FROM information_schema.columns WHERE table_schema='ops' AND table_name='access_events' AND column_name='event_time';")
echo "Result: $dtype"
echo "$dtype" | grep -qi "timestamp with time zone" && pass "Correct timestamp type" || fail "Wrong timestamp type"

echo
echo "Test 2.2: payments.amount is NUMERIC (not text)"
dtype=$(run "SELECT data_type FROM information_schema.columns WHERE table_schema='finance' AND table_name='payments' AND column_name='amount';")
echo "Result: $dtype"
echo "$dtype" | grep -qi "numeric" && pass "Correct amount type" || fail "Wrong amount type"

echo
echo "Test 2.3: UNIQUE(username) enforced (duplicate should fail)"
if sudo -u postgres psql -X -d "$DB" -c \
  "INSERT INTO identity.users(username,email,full_name,password_hash,level_id)
   VALUES ('alice','alice_dupe@student.edu','Alice Clone','hashX',(SELECT level_id FROM identity.access_levels LIMIT 1));" \
  >/dev/null 2>&1; then
  fail "Duplicate username insert unexpectedly succeeded"
else
  pass "Duplicate username blocked"
fi

echo
echo "Test 2.4: FK prevents orphan payment (expected fail)"
if sudo -u postgres psql -X -d "$DB" -c \
  "INSERT INTO finance.payments(user_id, method_id, amount, currency, status)
   VALUES (999999999, NULL, 10, 'GBP', 'pending');" \
  >/dev/null 2>&1; then
  fail "Orphan payment unexpectedly succeeded"
else
  pass "Orphan payment blocked by FK"
fi

section "3) Security mitigation tests (least privilege + PCI + audit + SQLi)"

echo "Test 3.1: Least privilege (student_user cannot SELECT ops.buildings)"
lp=$(run "SELECT has_table_privilege('student_user','ops.buildings','SELECT');")
echo "Result: $lp"
[[ "$lp" == "f" ]] && pass "Least privilege enforced" || fail "student_user has unexpected SELECT on ops.buildings"

echo
echo "Test 3.2: No plaintext card columns (PCI mitigation)"
cardcols=$(run "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='finance' AND column_name ILIKE '%card%';")
echo "Result: $cardcols"
[[ "$cardcols" == "0" ]] && pass "No card columns found" || fail "Card-like column found"

echo
echo "Test 3.3: Audit log contains security actions"
aud=$(run "SELECT COUNT(*) FROM audit.audit_log WHERE action IN ('GRANT_PERMISSION','UPDATE_PAYMENT_STATUS','UPDATE_CONFIG','ACCESS_GRANTED','ACCESS_DENIED');")
echo "Result: $aud"
[[ "$aud" -ge 1 ]] && pass "Audit log populated" || fail "Audit log not populated"

echo
echo "Test 3.4: SQL injection payload rejected by typing (expected fail)"
if sudo -u postgres psql -X -d "$DB" -c \
  "SELECT * FROM api.request_access($alice, '1 OR 1=1', NULL, '127.0.0.1'::inet);" \
  >/dev/null 2>&1; then
  fail "SQLi payload unexpectedly accepted"
else
  pass "SQLi payload rejected (typed params)"
fi

echo
echo "ALL TESTS PASSED"
