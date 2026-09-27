CREATE TABLE Users (
    UserID INT PRIMARY KEY,
    Username VARCHAR(50),
    Password VARCHAR(255),       
    FullName VARCHAR(255),
    Email VARCHAR(255),
    Role VARCHAR(20),            
    IsSuperUser INT DEFAULT 0,   
    Notes TEXT                  
);


CREATE TABLE Buildings (
    BuildingID INT PRIMARY KEY,
    Name VARCHAR(100),
    Zone VARCHAR(50),
    RequiredLevel VARCHAR(50)    
);


CREATE TABLE AccessLogs (
    LogID INT PRIMARY KEY,
    UserFullName VARCHAR(255),   
    BuildingName VARCHAR(100),   
    AccessTime VARCHAR(50),      
    Status VARCHAR(20),          
    EntryMessage TEXT            
);

CREATE TABLE Payments (
    PaymentID INT PRIMARY KEY,
    UserID INT,
    CardNumber VARCHAR(255),     
    ExpiryDate VARCHAR(10),      
    Amount VARCHAR(50),          
    TransactionToken TEXT        
);

CREATE TABLE SystemConfig (
    ConfigID INT PRIMARY KEY,
    ConfigKey VARCHAR(100),
    ConfigValue TEXT,            
    IsLocked BOOLEAN DEFAULT FALSE
);


CREATE TABLE Devices (
    DeviceID INT PRIMARY KEY,
    DeviceIP VARCHAR(45),
    AdminUser VARCHAR(50),
    AdminPass VARCHAR(255)       
);


CREATE TABLE Feedback (
    FeedbackID INT PRIMARY KEY,
    UserID INT,
    Comment TEXT,                
    Rating INT
);

CREATE TABLE Permissions (
    PermID INT PRIMARY KEY,
    UserID INT,
    BuildingID INT,
    OverrideCode VARCHAR(50)     
);