CREATE OR REPLACE PACKAGE XXCOM_LOGGING_PKG AUTHID CURRENT_USER AS
-- Source: modules/shared/plsql/XXCOM_LOGGING_PKG.pks
  gc_pkg_name         CONSTANT VARCHAR2(30) := 'XXCOM_LOGGING_PKG';
  gc_level_unexpected CONSTANT NUMBER := 6;
  gc_level_error      CONSTANT NUMBER := 5;
  gc_level_event      CONSTANT NUMBER := 3;
  gc_level_procedure  CONSTANT NUMBER := 2;
  gc_level_statement  CONSTANT NUMBER := 1;

  PROCEDURE log (p_module IN VARCHAR2, p_level IN NUMBER DEFAULT 1, p_message IN VARCHAR2, p_write_audit IN BOOLEAN DEFAULT FALSE);
  PROCEDURE log_error     (p_module IN VARCHAR2, p_message IN VARCHAR2);
  PROCEDURE log_event     (p_module IN VARCHAR2, p_message IN VARCHAR2);
  PROCEDURE log_statement (p_module IN VARCHAR2, p_message IN VARCHAR2);
  PROCEDURE write_audit_trail (
    p_module IN VARCHAR2, p_event_type IN VARCHAR2,
    p_object_type IN VARCHAR2, p_object_id IN NUMBER,
    p_old_value IN VARCHAR2 DEFAULT NULL, p_new_value IN VARCHAR2 DEFAULT NULL,
    p_description IN VARCHAR2 DEFAULT NULL
  );
END XXCOM_LOGGING_PKG;
/
