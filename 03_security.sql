SELECT * FROM mysql.user;

CREATE USER 'clinic_user'@'localhost' IDENTIFIED BY 'something';

GRANT SELECT, INSERT, UPDATE ON mydb.* TO 'clinic_user'@'localhost';