# Secure Campus Access Database

A security-focused PostgreSQL database designed for a fictional university campus access system.

The project redesigns an insecure database architecture into a normalised, access-controlled system using PostgreSQL schemas, role-based access control (RBAC), least-privilege permissions, restricted views, secure database functions, auditing, integrity constraints, and automated security testing.

## Overview

CampusAccess models a system used to manage users, buildings, access permissions, physical access events, payments, configuration data, and audit records.

The project includes both an intentionally problematic database design and a redesigned secure implementation, demonstrating how database security and data integrity can be improved through architectural and access-control changes.

The secure implementation separates sensitive functionality across dedicated PostgreSQL schemas:

- `identity` — users, roles, access levels and role assignments
- `ops` — buildings, devices, permissions and access events
- `finance` — payment-related information
- `config` — system configuration
- `audit` — security and audit records
- `api` — controlled views and functions exposed to application roles

## Security Features

### Role-Based Access Control

Dedicated PostgreSQL roles restrict users to the database functionality required for their responsibilities.

The design follows the principle of least privilege rather than granting application users direct access to all underlying tables.

### Schema Isolation

Database functionality is separated into security-focused schemas, reducing unnecessary access between different areas of the system.

For example, operational users do not automatically receive access to financial or audit information.

### Restricted API Layer

The `api` schema provides controlled views and functions through which users can interact with the database.

This reduces direct access to underlying tables and limits the information exposed to different roles.

### Secure Access Decisions

The database implements an access-request function that evaluates whether a user is permitted to access a building and records the resulting access event.

This provides a controlled interface for access decisions rather than allowing clients to directly manipulate access records.

### Database Auditing

Security-relevant operations are recorded in dedicated audit structures to provide accountability and traceability.

### Data Integrity

The redesigned database uses:

- Primary and foreign keys
- Unique constraints
- Appropriate PostgreSQL data types
- Referential integrity
- Domain and value constraints
- Normalised relational structures

These controls prevent several classes of inconsistent or invalid data that were possible in the original design.

### SQL Injection Resistance

Database functions and queries are designed to avoid unsafe dynamic SQL where possible.

The automated test suite also includes malicious-input testing to verify that SQL-injection-style input is handled as data rather than executable SQL.

## Automated Security Testing

The project includes a Bash test suite:

```bash
./test.sh
```

The tests verify both functionality and security controls, including:

- Database and schema creation
- Required tables and views
- API functions
- Sample data
- Role mappings
- Building access decisions
- Correct PostgreSQL data types
- Foreign-key enforcement
- Unique constraints
- Least-privilege permissions
- Restricted access to sensitive information
- Audit logging
- SQL-injection resistance

Tests return `PASS` or `FAIL` results to make verification straightforward.

## Project Structure

```text
secure-campus-database/
├── campus_access_problematic.sql
├── campus_access_solution.sql
├── setup.sh
├── test.sh
├── README.md
└── .gitignore
```

### `campus_access_problematic.sql`

Contains the original insecure database design used as the starting point for the security analysis.

### `campus_access_solution.sql`

Contains the redesigned PostgreSQL implementation, including schemas, tables, constraints, roles, permissions, views, functions, auditing and sample data.

### `setup.sh`

Automates creation of the `campus_access` PostgreSQL database and executes the secure build script.

### `test.sh`

Runs functional and security-focused tests against the completed database.

## Requirements

The project was developed for a Linux environment using PostgreSQL.

Required software:

- PostgreSQL
- Bash
- Linux or a compatible Unix-like environment

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
```

## Installation

Clone the repository:

```bash
git clone https://github.com/<your-username>/secure-campus-database.git
cd secure-campus-database
```

Make the scripts executable:

```bash
chmod +x setup.sh
chmod +x test.sh
```

Create and configure the database:

```bash
./setup.sh
```

The setup script creates the `campus_access` database if necessary and executes `campus_access_solution.sql`.

## Running the Tests

After setup:

```bash
./test.sh
```

The test suite checks that the database operates correctly and that the implemented security controls behave as expected.

## Design Approach

The project follows a defence-in-depth approach to database security.

Rather than relying on a single security mechanism, the design combines:

```text
Normalisation
      ↓
Data integrity constraints
      ↓
Schema separation
      ↓
Role-based access control
      ↓
Least-privilege permissions
      ↓
Restricted views and functions
      ↓
Audit logging
      ↓
Automated security testing
```

This demonstrates how security can be incorporated directly into database architecture rather than being added only at the application layer.

## Technologies

- PostgreSQL
- SQL
- Bash
- Role-Based Access Control (RBAC)
- Database auditing
- Relational database design
- Automated security testing

## Purpose

This project was developed as part of my practical cybersecurity work and demonstrates secure database design, access-control implementation, security testing, and PostgreSQL administration.

The repository focuses on the technical implementation and has been prepared as a portfolio version of the original project.
