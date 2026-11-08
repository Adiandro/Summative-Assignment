use crowfield_hospital_s3;

-- C1. AGGREGATE QUERY: GROUP BY + HAVING
-- Purpose: Find clinicians with more than 2 appointments.
-- Explanation: Appointments are grouped per clinician.

SELECT  c.ClinicianID,
        c.ClinicianName,
        c.Specialty,
        COUNT(a.AppointmentID) AS TotalAppointments
FROM    CLINICAL c
JOIN    APPOINTMENT a ON a.CLINICAL_ClinicianID = c.ClinicianID
GROUP BY c.ClinicianID, c.ClinicianName, c.Specialty
HAVING  COUNT(a.AppointmentID) > 2
ORDER BY TotalAppointments DESC;


-- C2. INNER JOIN across at least three related tables
-- Purpose: To make a readable appointment by connecting information from other tables related to the scheduling.
-- Explanation: INNER JOIN will return the information required and join them together to create a full appointment for each person.

SELECT  p.PatientName,
        a.AppointmentDate,
        a.AppointmentTime,
        c.ClinicianName,
        cl.LocationName
FROM APPOINTMENT a
INNER JOIN PATIENT p ON p.PatientID = a.PATIENT_PatientID
INNER JOIN CLINICAL c ON c.ClinicianID = a.CLINICAL_ClinicianID
INNER JOIN CLINIC_LOCATION cl ON cl.ClinicID = a.CLINIC_LOCATION_ClinicID
ORDER BY a.AppointmentDate, a.AppointmentTime;


-- C3. LEFT JOIN revealing missing or optional data
-- Purpose: List every appointment and show whether a follow-up plan exists.
-- Follow-up is optional as some appointments might not have a follow-up.
-- Explanation: LEFT JOIN keeps all appointments and shows which follow-up plans are empty and are shown as NULL

SELECT  a.AppointmentID,
        a.AppointmentDate,
        p.PatientName,
        f.PlanID,
        f.UrgencyLevel,
        f.TargetPeriod
FROM    APPOINTMENT a
JOIN    PATIENT p ON p.PatientID = a.PATIENT_PatientID
LEFT JOIN FOLLOW_UP_PLAN f ON f.APPOINTMENT_AppointmentID = a.AppointmentID
ORDER BY a.AppointmentDate;

-- Variation: only appointments with NO follow-up plan
SELECT  a.AppointmentID, a.AppointmentDate, p.PatientName
FROM    APPOINTMENT a
JOIN    PATIENT p ON p.PatientID = a.PATIENT_PatientID
LEFT JOIN FOLLOW_UP_PLAN f ON f.APPOINTMENT_AppointmentID = a.AppointmentID
WHERE   f.PlanID IS NULL;


-- C4. COMMON TABLE EXPRESSION + SUBQUERY
-- Purpose: To find patients that attend more frequent than other patients
-- Explanation: Common table expression is used to count appointments per patient, while subquery shows the average of those counts
WITH patient_visits AS (
    SELECT  PATIENT_PatientID AS PatientID,
            COUNT(*)          AS Visits
    FROM    APPOINTMENT
    GROUP BY PATIENT_PatientID
)
SELECT  p.PatientID,
        p.PatientName,
        pv.Visits
FROM    patient_visits pv
JOIN    PATIENT p ON p.PatientID = pv.PatientID
WHERE   pv.Visits > (SELECT AVG(Visits) FROM patient_visits)
ORDER BY pv.Visits DESC;


-- C5. Stored procedure with an input parameter
-- Purpose: To show a patients previous appointments
-- Explanation: p_patient_id will be used for all patients as the code works with all patientID

DROP PROCEDURE IF EXISTS GetPatientHistory;
DELIMITER //
CREATE PROCEDURE GetPatientHistory(IN p_patient_id VARCHAR(6))
BEGIN
    SELECT  p.PatientName,
            a.AppointmentID,
            a.AppointmentDate,
            a.AppointmentTime,
            c.ClinicianName,
            cl.LocationName,
            a.ClinicalNotes
    FROM    APPOINTMENT a
    JOIN    PATIENT p         ON p.PatientID = a.PATIENT_PatientID
    JOIN    CLINICAL c        ON c.ClinicianID = a.CLINICAL_ClinicianID
    JOIN    CLINIC_LOCATION cl ON cl.ClinicID = a.CLINIC_LOCATION_ClinicID
    WHERE   a.PATIENT_PatientID = p_patient_id
    ORDER BY a.AppointmentDate, a.AppointmentTime;
END //
DELIMITER ;

CALL GetPatientHistory('OP001');


-- C6. Trigger enforcing a business rule
-- Purpose: To constrain invalid dates and to make sure a clinician cannot be booked twice.
-- Explanation: Due to dates being used as VARCHAR the database will not automatically refuse invalid dates which is why the trigger will be used.

DROP TRIGGER IF EXISTS trg_appointment_validate;
DELIMITER //
CREATE TRIGGER trg_appointment_validate
BEFORE INSERT ON APPOINTMENT
FOR EACH ROW
BEGIN
    -- (1) Date must be a valid YYYY-MM-DD date
    IF STR_TO_DATE(NEW.AppointmentDate, '%Y-%m-%d') IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid appointment date. Use format YYYY-MM-DD.';
    END IF;

    -- (2) No double-booking of a clinician
    IF EXISTS (
        SELECT 1
        FROM   APPOINTMENT
        WHERE  CLINICAL_ClinicianID = NEW.CLINICAL_ClinicianID
          AND  AppointmentDate      = NEW.AppointmentDate
          AND  AppointmentTime      = NEW.AppointmentTime
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Clinician already has an appointment at this date and time.';
    END IF;
END //
DELIMITER ;

-- Test 1 (should FAIL, invalid date):
INSERT INTO appointment (AppointmentID, AppointmentDate, AppointmentTime, ClinicalNotes, PATIENT_PatientID, CLINICAL_ClinicianID, CLINIC_LOCATION_ClinicID)
VALUES (999, '2026-13-45', '09:00', 'Test', 'OP001', 1, 1);

-- Test 2 (should SUCCEED, valid date and free slot):
INSERT INTO appointment (AppointmentID, AppointmentDate, AppointmentTime, ClinicalNotes, PATIENT_PatientID, CLINICAL_ClinicianID, CLINIC_LOCATION_ClinicID)
VALUES (1000, '2026-11-20', '09:00', 'Test', 'OP001', 1, 1);

-- Running Test 2 a second time with a new AppointmentID should FAIL (double-booking).
