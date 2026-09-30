# University Course Registration System

## About the Project

The **University Course Registration System** is a relational database project developed using **Microsoft SQL Server**.

The system is designed to manage the university course registration process, including students, lecturers, departments, courses, course offerings, prerequisites, enrollments, grades, and academic transcripts.

This project was developed as part of the **ICDT1202Y – Database Systems** module at the University of Mauritius.

## Features

- Student and lecturer management
- Department and course management
- Course prerequisite validation
- Student course enrollment
- Course capacity checking
- Grade recording
- Automatic enrollment status updates
- Student transcript generation
- Department course statistics
- Prevention of circular prerequisites
- Role-based database security
- SQL constraints for data integrity

## Database Design

The database contains the following main tables:

- `Department`
- `Lecturer`
- `Course`
- `Prerequisite`
- `CourseOffering`
- `Student`
- `Enrollment`

The database was normalized up to **Third Normal Form (3NF)** to reduce redundancy and maintain data integrity.

## Entity Relationship Diagram

![University Course Registration System ERD](screenshots/erd.png)

## Stored Procedures

The project implements several stored procedures:

### `usp_EnrollStudent`

Enrolls a student into a course offering while checking prerequisites and preventing duplicate enrollment.

### `usp_RecordGrade`

Records a student's final grade for a course.

### `usp_GetTranscript`

Generates a student's academic transcript containing course information, semester, lecturer, grade, and letter grade.

### `usp_DeptCourseStats`

Generates course statistics including enrollment numbers, remaining places, fill rate, average grades, and pass/fail counts.

## Triggers

The database uses triggers to automatically enforce important business rules.

### `trg_CheckCapacity`

Prevents students from enrolling when a course offering has reached its maximum capacity.

### `trg_AutoCompleteOnGrade`

Automatically changes an enrollment status to `Completed` or `Failed` when a grade is recorded.

### `trg_NoCircularPrereq`

Prevents circular prerequisite relationships between courses.

## Database Security

Three SQL Server roles are used:

- `db_student`
- `db_lecturer`
- `db_admin`

Different permissions are assigned to each role using `GRANT` and `DENY` statements to implement role-based access control.

## Testing

The database was tested for scenarios including:

- Successful enrollment
- Course capacity limits
- Prerequisite validation
- Grade recording
- Automatic status updates
- Transcript generation
- Department statistics
- Circular prerequisite prevention
- Duplicate enrollment prevention

## Technologies Used

- SQL
- Microsoft SQL Server
- SQL Server Management Studio (SSMS)
- T-SQL
- Relational Database Design
- Entity Relationship Diagrams (ERD)
- Database Normalization

## Project Structure

```text
university-course-registration-system/
│
├── README.md
├── University Course Registration System.sql
│
└── screenshots/
    ├── erd.png
    ├── database-tables.png
    └── test-results.png
```

## My Contribution

This was a group database project.

My individual contribution included:

- Implementation of `trg_CheckCapacity`
- Implementation of `trg_AutoCompleteOnGrade`
- Implementation of `trg_NoCircularPrereq`
- Database security and role creation
- `GRANT` and `DENY` permissions
- Project report Sections 6–8
- Final project compilation

