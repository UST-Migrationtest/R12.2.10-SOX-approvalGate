CREATE OR REPLACE PACKAGE BODY XXCOM_LOGGING_PKG AS

  -- ============================================================
  -- Private: Map severity string to FND_LOG level constant
  -- ============================================================
  FUNCTION get_fnd_level(p_severity IN VARCHAR2) RETURN NUMBER IS
  BEGIN
    RETURN CASE UPPER(p_severity)
      WHEN 'STATEMENT'  THEN FND_LOG.LEVEL_STATEMENT
      WHEN 'PROCEDURE'  THEN FND_LOG.LEVEL_PROCEDURE
      WHEN 'EVENT'      THEN FND_LOG.LEVEL_EVENT
      WHEN 'EXCEPTION'  THEN FND_LOG.LEVEL_EXCEPTION
      WHEN 'ERROR'      THEN FND_LOG.LEVEL_ERROR
      WHEN 'UNEXPECTED' THEN FND_LOG.LEVEL_UNEXPECTED
      ELSE FND_LOG.LEVEL_STATEMENT
    END;
  END get_fnd_level;

  -- ============================================================
  -- Primary logging procedure
  -- ============================================================
  PROCEDURE log_message(
    p_module      IN VARCHAR2,
    p_severity    IN VARCHAR2,
    p_message     IN VARCHAR2,
    p_context     IN VARCHAR2 DEFAULT NULL
  ) IS
    l_fnd_level  NUMBER;
    l_module_key VARCHAR2(500);
    l_message    VARCHAR2(4000);
  BEGIN
    l_fnd_level  := get_fnd_level(p_severity);
    l_module_key := 'oracle.apps.xxcom.' || LOWER(p_module);
    l_message    := p_message;

    IF p_context IS NOT NULL THEN
      l_message := l_message || ' [Context: ' || p_context || ']';
    END IF;

    IF FND_LOG.LEVEL_STATEMENT >= FND_LOG.G_CURRENT_RUNTIME_LEVEL THEN
      FND_LOG.STRING(
        log_level => l_fnd_level,
        module    => l_module_key,
        message   => SUBSTR(l_message, 1, 4000)
      );
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      NULL; -- Logging must never raise exceptions
  END log_message;

  -- ============================================================
  -- Convenience wrappers
  -- ============================================================
  PROCEDURE log_info(p_module IN VARCHAR2, p_message IN VARCHAR2) IS
  BEGIN
    log_message(p_module, 'EVENT', p_message);
  END log_info;

  PROCEDURE log_error(
    p_module    IN VARCHAR2,
    p_message   IN VARCHAR2,
    p_sqlerrm   IN VARCHAR2 DEFAULT NULL
  ) IS
    l_full_msg VARCHAR2(4000);
  BEGIN
    l_full_msg := p_message;
    IF p_sqlerrm IS NOT NULL THEN
      l_full_msg := l_full_msg || ' | SQLERRM: ' || p_sqlerrm;
    END IF;
    log_message(p_module, 'ERROR', l_full_msg);
  END log_error;

  PROCEDURE log_debug(p_module IN VARCHAR2, p_message IN VARCHAR2) IS
  BEGIN
    log_message(p_module, 'STATEMENT', p_message);
  END log_debug;

  -- ============================================================
  -- Audit trail — autonomous so it commits independently
  -- ============================================================
  PROCEDURE write_audit_trail(
    p_module      IN VARCHAR2,
    p_event_type  IN VARCHAR2,
    p_object_id   IN NUMBER,
    p_old_value   IN VARCHAR2 DEFAULT NULL,
    p_new_value   IN VARCHAR2 DEFAULT NULL,
    p_performed_by IN VARCHAR2 DEFAULT NULL
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_user VARCHAR2(100);
  BEGIN
    l_user := NVL(p_performed_by, FND_GLOBAL.USER_NAME);

    INSERT INTO XXCOM_AUDIT_TRAIL (
      audit_id,
      module_code,
      event_type,
      object_id,
      old_value,
      new_value,
      performed_by,
      event_timestamp,
      session_id,
      request_id
    ) VALUES (
      XXCOM_AUDIT_TRAIL_S.NEXTVAL,
      UPPER(p_module),
      UPPER(p_event_type),
      p_object_id,
      SUBSTR(p_old_value, 1, 4000),
      SUBSTR(p_new_value, 1, 4000),
      l_user,
      SYSTIMESTAMP,
      USERENV('SESSIONID'),
      FND_GLOBAL.CONC_REQUEST_ID
    );

    COMMIT;

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      -- Log the audit failure itself (best-effort, no recursion)
      FND_LOG.STRING(
        FND_LOG.LEVEL_UNEXPECTED,
        'oracle.apps.xxcom.logging',
        'AUDIT TRAIL WRITE FAILED: ' || SQLERRM
      );
  END write_audit_trail;

END XXCOM_LOGGING_PKG;
/
