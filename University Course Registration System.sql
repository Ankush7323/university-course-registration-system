CREATE DATABASE UniversityCourseRegistration;
GO
USE UniversityCourseRegistration;
GO
 
-- Department goes first; we add the head lecturer FK after Lecturer exists
CREATE TABLE Department 
   (DeptID         INT PRIMARY KEY IDENTITY(1,1),
    DeptName       VARCHAR(100) NOT NULL UNIQUE,
    Location       VARCHAR(100),
    HeadLecturerID INT NULL);
 
CREATE TABLE Lecturer 
   (LecturerID INT PRIMARY KEY IDENTITY(1,1),
    FirstName  VARCHAR(50) NOT NULL,
    LastName   VARCHAR(50) NOT NULL,
    Email      VARCHAR(100) NOT NULL UNIQUE,
    DeptID     INT NOT NULL,
    CONSTRAINT FK_Lecturer_Dept FOREIGN KEY (DeptID) REFERENCES Department(DeptID) );
 
-- now Lecturer exists so we can wire up the head of dept reference
ALTER TABLE Department
    ADD CONSTRAINT FK_Dept_Head FOREIGN KEY (HeadLecturerID) REFERENCES Lecturer(LecturerID);
 
CREATE TABLE Course 
   (CourseID   INT PRIMARY KEY IDENTITY(1,1),
    CourseCode VARCHAR(20) NOT NULL UNIQUE,
    CourseName VARCHAR(150) NOT NULL,
    Credits    TINYINT NOT NULL CHECK(Credits BETWEEN 1 AND 6),
    DeptID     INT NOT NULL,
    CONSTRAINT FK_Course_Dept FOREIGN KEY (DeptID) REFERENCES Department(DeptID));

 
-- prereqs are just a self-referencing join on Course
CREATE TABLE Prerequisite 
   (CourseID       INT NOT NULL,
    PrereqCourseID INT NOT NULL,
    CONSTRAINT PK_Prerequisite PRIMARY KEY (CourseID, PrereqCourseID),
    CONSTRAINT FK_Prereq_Course FOREIGN KEY (CourseID) REFERENCES Course(CourseID),
    CONSTRAINT FK_Prereq_Pre FOREIGN KEY (PrereqCourseID) REFERENCES Course(CourseID),
    CONSTRAINT CHK_NoSelfPrereq CHECK (CourseID <> PrereqCourseID));

 
CREATE TABLE CourseOffering 
   (OfferingID INT PRIMARY KEY IDENTITY(1,1),
    CourseID   INT NOT NULL,
    LecturerID INT NOT NULL,
    Semester   VARCHAR(10) NOT NULL CHECK(Semester IN ('Semester1','Semester2','Summer')),
    Year       SMALLINT NOT NULL CHECK(Year BETWEEN 2000 AND 2100),
    Capacity   SMALLINT NOT NULL CHECK(Capacity > 0),
    Room       VARCHAR(20),
    CONSTRAINT FK_Offering_Course FOREIGN KEY (CourseID) REFERENCES Course(CourseID),
    CONSTRAINT FK_Offering_Lecturer FOREIGN KEY (LecturerID) REFERENCES Lecturer(LecturerID)
);

 
CREATE TABLE Student 
   (StudentID   INT PRIMARY KEY IDENTITY(1,1),
    FirstName   VARCHAR(50) NOT NULL,
    LastName    VARCHAR(50) NOT NULL,
    Email       VARCHAR(100) NOT NULL UNIQUE,
    DateOfBirth DATE,
    DeptID      INT NOT NULL,
    CONSTRAINT FK_Student_Dept FOREIGN KEY (DeptID) REFERENCES Department(DeptID)
);
 
CREATE TABLE Enrollment 
   (EnrollmentID INT PRIMARY KEY IDENTITY(1,1),
    StudentID    INT NOT NULL,
    OfferingID   INT NOT NULL,
    EnrollDate   DATE NOT NULL DEFAULT GETDATE(),
    Grade        DECIMAL(4,2) NULL CHECK(Grade BETWEEN 0 AND 100),
    Status       VARCHAR(20) NOT NULL DEFAULT 'Registered'
                 CHECK(Status IN ('Registered','Completed','Withdrawn','Failed')),
    CONSTRAINT FK_Enroll_Student FOREIGN KEY (StudentID) REFERENCES Student(StudentID),
    CONSTRAINT FK_Enroll_Offering FOREIGN KEY (OfferingID) REFERENCES CourseOffering(OfferingID),
    CONSTRAINT UQ_Enrollment UNIQUE (StudentID, OfferingID));


-- block the insert if the offering is already at capacity
CREATE TRIGGER trg_CheckCapacity
ON Enrollment
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM inserted i
        JOIN CourseOffering co ON co.OfferingID = i.OfferingID
        LEFT JOIN (
            SELECT OfferingID, COUNT(*) AS CurrentCount
            FROM Enrollment WHERE Status = 'Registered'
            GROUP BY OfferingID
        ) ec ON ec.OfferingID = i.OfferingID
        WHERE ISNULL(ec.CurrentCount, 0) >= co.Capacity)
    BEGIN
        RAISERROR('Cannot enroll: offering is at full capacity.', 16, 1);
        RETURN;
    END
    -- all good, trigger will do the real capacity check too
    INSERT INTO Enrollment (StudentID, OfferingID, EnrollDate, Grade, Status)
    SELECT StudentID, OfferingID, EnrollDate, Grade, Status FROM inserted;
END;
GO
 
-- grade just got recorded, update the status automatically
CREATE TRIGGER trg_AutoCompleteOnGrade
ON Enrollment
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Enrollment SET Status = 'Completed'
    FROM Enrollment e JOIN inserted i ON e.EnrollmentID = i.EnrollmentID
    WHERE i.Grade IS NOT NULL AND i.Grade >= 40 AND e.Status = 'Registered';
 
    UPDATE Enrollment SET Status = 'Failed'
    FROM Enrollment e JOIN inserted i ON e.EnrollmentID = i.EnrollmentID
    WHERE i.Grade IS NOT NULL AND i.Grade < 40 AND e.Status = 'Registered';
END;
GO
 
-- walk the prereq chain upward; bail if we loop back to the course we started with
CREATE TRIGGER trg_NoCircularPrereq
ON Prerequisite
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsCircular INT = 0;

    ;WITH prereq_chain AS (
        SELECT PrereqCourseID AS AncestorID
        FROM Prerequisite
        WHERE CourseID IN (SELECT PrereqCourseID FROM inserted)
        UNION ALL
        SELECT p.PrereqCourseID
        FROM Prerequisite p
        JOIN prereq_chain pc ON p.CourseID = pc.AncestorID
    )
    SELECT @IsCircular = 1
    FROM prereq_chain
    JOIN inserted i ON prereq_chain.AncestorID = i.CourseID;

    IF @IsCircular = 1
    BEGIN
        RAISERROR('Circular prerequisite detected, insert cancelled.', 16, 1);
        RETURN;
    END

    INSERT INTO Prerequisite SELECT * FROM inserted;
END;
GO

-- prereq check lives here; capacity check is handled by the INSTEAD OF trigger
CREATE PROCEDURE usp_EnrollStudent
    @StudentID  INT,
    @OfferingID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CourseID INT;
    SELECT @CourseID = CourseID FROM CourseOffering WHERE OfferingID = @OfferingID;
 
    -- any missing prereqs? bail out early
    IF EXISTS (
        SELECT p.PrereqCourseID FROM Prerequisite p
        WHERE p.CourseID = @CourseID
        AND p.PrereqCourseID NOT IN (
            SELECT co.CourseID FROM Enrollment e
            JOIN CourseOffering co ON co.OfferingID = e.OfferingID
            WHERE e.StudentID = @StudentID AND e.Status = 'Completed'
        )
    )
    BEGIN
        RAISERROR('Cannot enroll: prerequisites not completed.', 16, 1);
        RETURN;
    END
 
    IF EXISTS (SELECT 1 FROM Enrollment WHERE StudentID = @StudentID AND OfferingID = @OfferingID)
    BEGIN
        RAISERROR('Already enrolled in this offering.', 16, 1);
        RETURN;
    END
 
    INSERT INTO Enrollment (StudentID, OfferingID, EnrollDate, Status)
    VALUES (@StudentID, @OfferingID, GETDATE(), 'Registered');
END;
GO
 
CREATE PROCEDURE usp_RecordGrade
    @StudentID  INT,
    @OfferingID INT,
    @Grade      DECIMAL(4,2)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Enrollment WHERE StudentID = @StudentID AND OfferingID = @OfferingID)
    BEGIN
        RAISERROR('No enrollment record found.', 16, 1);
        RETURN;
    END
    UPDATE Enrollment
    SET Grade = @Grade
    WHERE StudentID = @StudentID AND OfferingID = @OfferingID;
END;
GO
 
-- pull everything we need for the transcript in one shot
CREATE PROCEDURE usp_GetTranscript @StudentID INT
AS
BEGIN
    SELECT
        s.FirstName + ' ' + s.LastName AS StudentName,
        c.CourseCode,
        c.CourseName,
        c.Credits,
        co.Semester,
        co.Year,
        l.FirstName + ' ' + l.LastName AS Lecturer,
        e.Grade,
        e.Status,
        CASE
            WHEN e.Grade IS NULL THEN 'N/A'
            WHEN e.Grade >= 70 THEN 'A'
            WHEN e.Grade >= 60 THEN 'B'
            WHEN e.Grade >= 50 THEN 'C'
            WHEN e.Grade >= 40 THEN 'D'
            ELSE 'F'
        END AS LetterGrade
    FROM Enrollment e
    JOIN Student s ON s.StudentID = e.StudentID
    JOIN CourseOffering co ON co.OfferingID = e.OfferingID
    JOIN Course c ON c.CourseID = co.CourseID
    JOIN Lecturer l ON l.LecturerID = co.LecturerID
    WHERE e.StudentID = @StudentID
    ORDER BY co.Year DESC, co.Semester;
END;
GO
 
-- one row per offering: fill rate, avg grade, pass/fail breakdown
CREATE PROCEDURE usp_DeptCourseStats @DeptID INT
AS
BEGIN
    SELECT
        c.CourseCode,
        c.CourseName,
        co.Semester,
        co.Year,
        co.Capacity,
        COUNT(e.EnrollmentID) AS TotalEnrolled,
        co.Capacity - COUNT(e.EnrollmentID) AS SlotsRemaining,
        CAST(COUNT(e.EnrollmentID) AS FLOAT) / co.Capacity * 100 AS FillRate,
        AVG(e.Grade) AS AvgGrade,
        COUNT(CASE WHEN e.Grade IS NOT NULL THEN 1 END) AS GradedCount,

        SUM(CASE WHEN e.Status = 'Completed' THEN 1 ELSE 0 END) AS Passed,
        SUM(CASE WHEN e.Status = 'Failed'    THEN 1 ELSE 0 END) AS Failed
    FROM Course c
    JOIN CourseOffering co ON co.CourseID = c.CourseID
    LEFT JOIN Enrollment e ON e.OfferingID = co.OfferingID AND e.Status <> 'Withdrawn'
    WHERE c.DeptID = @DeptID
    GROUP BY c.CourseCode, c.CourseName, co.Semester, co.Year, co.Capacity
    ORDER BY co.Year DESC, co.Semester, c.CourseCode;
END;
GO


CREATE ROLE db_student;
CREATE ROLE db_lecturer;
CREATE ROLE db_admin;
 
-- students: read-only on most things, can enroll and view their transcript
GRANT SELECT ON Student TO db_student;
GRANT SELECT ON Course TO db_student;
GRANT SELECT ON CourseOffering TO db_student;
GRANT SELECT ON Enrollment TO db_student;
GRANT EXECUTE ON usp_EnrollStudent TO db_student;
GRANT EXECUTE ON usp_GetTranscript TO db_student;
DENY DELETE ON Enrollment TO db_student;
DENY UPDATE ON Enrollment TO db_student;
 
-- lecturers: see who is in their classes, enter grades
GRANT SELECT ON CourseOffering TO db_lecturer;
GRANT SELECT ON Enrollment TO db_lecturer;
GRANT SELECT ON Student TO db_lecturer;
GRANT EXECUTE ON usp_RecordGrade TO db_lecturer;
GRANT EXECUTE ON usp_DeptCourseStats TO db_lecturer;
 
-- admin gets full CRUD on everything
GRANT SELECT, INSERT, UPDATE, DELETE ON Department TO db_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON Lecturer TO db_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON Course TO db_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON Prerequisite TO db_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON CourseOffering TO db_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON Student TO db_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON Enrollment TO db_admin;
GRANT EXECUTE ON usp_EnrollStudent TO db_admin;
GRANT EXECUTE ON usp_RecordGrade TO db_admin;
GRANT EXECUTE ON usp_GetTranscript TO db_admin;
GRANT EXECUTE ON usp_DeptCourseStats TO db_admin;


-- 1. Test Insertion of Data
-- Departments
INSERT INTO Department (DeptName, Location)
VALUES 
('Computer Science', 'Block A'),
('Business', 'Block B');

-- Lecturers
INSERT INTO Lecturer (FirstName, LastName, Email, DeptID)
VALUES
('John', 'Smith', 'john.smith@uni.com', 1),
('Alice', 'Brown', 'alice.brown@uni.com', 1);

-- Assign Head of Department
UPDATE Department
SET HeadLecturerID = 1
WHERE DeptID = 1;

-- Courses
INSERT INTO Course (CourseCode, CourseName, Credits, DeptID)
VALUES
('CS101', 'Intro to Programming', 3, 1),
('CS102', 'Data Structures', 3, 1);

-- Prerequisite (CS101 → CS102)
INSERT INTO Prerequisite (CourseID, PrereqCourseID)
VALUES (2, 1);

-- Course Offering
INSERT INTO CourseOffering (CourseID, LecturerID, Semester, Year, Capacity, Room)
VALUES
(1, 1, 'Semester1', 2026, 2, 'A101'),
(2, 2, 'Semester1', 2026, 2, 'A102');

-- Students
INSERT INTO Student (FirstName, LastName, Email, DateOfBirth, DeptID)
VALUES
('Tom', 'Lee', 'tom.lee@uni.com', '2003-05-10', 1),
('Sara', 'Ali', 'sara.ali@uni.com', '2002-08-20', 1),
('Mike', 'Roy', 'mike.roy@uni.com', '2003-01-15', 1);

-- 2. Test Enrollment (Normal Case)
EXEC usp_EnrollStudent @StudentID = 1, @OfferingID = 1;
EXEC usp_EnrollStudent @StudentID = 2, @OfferingID = 1;

-- 3. Test Capacity Trigger
EXEC usp_EnrollStudent @StudentID = 3, @OfferingID = 1;

-- 4. Test Prerequisite Check
EXEC usp_EnrollStudent @StudentID = 1, @OfferingID = 2;

-- 5. Complete First Course
EXEC usp_RecordGrade @StudentID = 1, @OfferingID = 1, @Grade = 75;

-- 6. Retry Enrollment (Should Now Work)
EXEC usp_EnrollStudent @StudentID = 1, @OfferingID = 2;

-- 7. Test Auto Fail
EXEC usp_RecordGrade @StudentID = 2, @OfferingID = 1, @Grade = 30;

-- 8. View Transcript
EXEC usp_GetTranscript @StudentID = 1;

-- 9. Department Stats
EXEC usp_DeptCourseStats @DeptID = 1;

-- 10. Test Circular Prerequisite
INSERT INTO Prerequisite (CourseID, PrereqCourseID)
VALUES (1, 2);
