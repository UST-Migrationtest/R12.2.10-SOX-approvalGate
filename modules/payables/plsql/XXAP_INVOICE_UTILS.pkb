CREATE OR REPLACE PACKAGE BODY XXAP_INVOICE_UTILS AS
-- =============================================================================
-- Source  : modules/payables/plsql/XXAP_INVOICE_UTILS.pkb
-- Deployed via MOD-03 SOX-gated pipeline (CHG0094127)
-- =============================================================================

  PROCEDURE validate_invoice (
    p_api_version    IN  NUMBER     DEFAULT 1.0,
    p_invoice_id     IN  NUMBER,
    p_org_id         IN  NUMBER,
    p_calling_module IN  VARCHAR2   DEFAULT NULL,
    x_return_status  OUT NOCOPY VARCHAR2,
    x_msg_count      OUT NOCOPY NUMBER,
    x_msg_data       OUT NOCOPY VARCHAR2
  ) IS
    lc_proc  CONSTANT VARCHAR2(30) := 'validate_invoice';
    l_inv_status  ap_invoices_all.approval_status_lookup_code%TYPE;
    l_inv_amount  ap_invoices_all.invoice_amount%TYPE;
    l_fnd_status  BOOLEAN;
  BEGIN
    x_return_status := gc_ret_success;
    FND_MSG_PUB.Initialize;

    FND_LOG.STRING(FND_LOG.LEVEL_PROCEDURE, gc_pkg_name || '.' || lc_proc,
                   'START: p_invoice_id=' || p_invoice_id || ' p_org_id=' || p_org_id);

    SELECT ai.approval_status_lookup_code, ai.invoice_amount
    INTO   l_inv_status, l_inv_amount
    FROM   ap_invoices_all ai
    WHERE  ai.invoice_id = p_invoice_id
    AND    ai.org_id     = p_org_id;

    IF l_inv_status = 'CANCELLED' THEN
      FND_MESSAGE.SET_NAME('XXAP', 'XXAP_INV_ALREADY_CANCELLED');
      FND_MSG_PUB.Add;
      x_return_status := gc_ret_error;
      RETURN;
    END IF;

    IF NVL(l_inv_amount, 0) = 0 THEN
      FND_MESSAGE.SET_NAME('XXAP', 'XXAP_INV_ZERO_AMOUNT');
      FND_MSG_PUB.Add;
      x_return_status := gc_ret_error;
    END IF;

    FND_MSG_PUB.Count_And_Get(p_count => x_msg_count, p_data => x_msg_data);

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      x_return_status := gc_ret_error;
      FND_MESSAGE.SET_NAME('XXAP', 'XXAP_INV_NOT_FOUND');
      FND_MSG_PUB.Add;
      FND_MSG_PUB.Count_And_Get(p_count => x_msg_count, p_data => x_msg_data);
    WHEN OTHERS THEN
      x_return_status := gc_ret_unexp;
      FND_MESSAGE.SET_NAME('FND', 'FND_AS_UNEXPECTED_ERROR');
      FND_MESSAGE.SET_TOKEN('PKG_NAME', gc_pkg_name);
      FND_MESSAGE.SET_TOKEN('PROC_NAME', lc_proc);
      FND_MESSAGE.SET_TOKEN('SQLERRM', SQLERRM);
      FND_MSG_PUB.Add;
      FND_MSG_PUB.Count_And_Get(p_count => x_msg_count, p_data => x_msg_data);
  END validate_invoice;

  PROCEDURE validate_3way_match (
    p_invoice_id     IN  NUMBER,
    p_po_header_id   IN  NUMBER,
    p_tolerance_pct  IN  NUMBER    DEFAULT 5,
    x_return_status  OUT NOCOPY VARCHAR2,
    x_match_status   OUT NOCOPY VARCHAR2,
    x_variance_amt   OUT NOCOPY NUMBER
  ) IS
    l_po_amount   NUMBER;
    l_inv_amount  NUMBER;
    l_variance    NUMBER;
  BEGIN
    x_return_status := gc_ret_success;
    x_match_status  := 'MATCHED';

    SELECT NVL(SUM(poll.amount), 0)
    INTO   l_po_amount
    FROM   po_line_locations_all poll
    WHERE  poll.po_header_id = p_po_header_id
    AND    poll.approved_flag = 'Y';

    l_inv_amount := get_invoice_amount(p_invoice_id, 'NET');
    l_variance   := ABS(l_po_amount - l_inv_amount);
    x_variance_amt := l_variance;

    IF l_po_amount > 0 AND (l_variance / l_po_amount * 100) > p_tolerance_pct THEN
      x_match_status  := 'VARIANCE';
      x_return_status := gc_ret_error;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      x_return_status := gc_ret_unexp;
      x_match_status  := 'ERROR';
  END validate_3way_match;

  FUNCTION get_invoice_amount (
    p_invoice_id  IN  NUMBER,
    p_amount_type IN  VARCHAR2  DEFAULT 'TOTAL'
  ) RETURN NUMBER IS
    l_amount  NUMBER;
  BEGIN
    SELECT CASE p_amount_type
             WHEN 'TOTAL' THEN NVL(ai.invoice_amount, 0)
             WHEN 'TAX'   THEN NVL(ai.total_tax_amount, 0)
             WHEN 'BASE'  THEN NVL(ai.base_amount, ai.invoice_amount)
             ELSE NVL(ai.invoice_amount, 0) - NVL(ai.total_tax_amount, 0)
           END
    INTO   l_amount
    FROM   ap_invoices_all ai
    WHERE  ai.invoice_id = p_invoice_id;
    RETURN NVL(l_amount, 0);
  EXCEPTION
    WHEN OTHERS THEN RETURN 0;
  END get_invoice_amount;

  PROCEDURE log_invoice_event (
    p_invoice_id  IN  NUMBER,
    p_event_type  IN  VARCHAR2,
    p_event_msg   IN  VARCHAR2,
    p_user_id     IN  NUMBER  DEFAULT FND_GLOBAL.USER_ID
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO xxap_invoice_audit_log (
      audit_log_id, invoice_id, event_type, event_message,
      created_by, creation_date, session_id
    ) VALUES (
      xxap_invoice_audit_log_s.NEXTVAL, p_invoice_id,
      p_event_type, SUBSTR(p_event_msg, 1, 4000),
      p_user_id, SYSDATE, USERENV('SESSIONID')
    );
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN ROLLBACK;
  END log_invoice_event;

END XXAP_INVOICE_UTILS;
/
