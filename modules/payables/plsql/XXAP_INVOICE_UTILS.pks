CREATE OR REPLACE PACKAGE XXAP_INVOICE_UTILS AUTHID CURRENT_USER AS
-- =============================================================================
-- Package Name    : XXAP_INVOICE_UTILS
-- Application     : Accounts Payable (AP)
-- Description     : Custom AP Invoice utility package deployed via MOD-03
--                   SOX-gated CI/CD pipeline. All changes to this package
--                   require 2 PR approvals and SoD compliance (CODEOWNERS).
-- Source          : modules/payables/plsql/XXAP_INVOICE_UTILS.pks
-- Version         : 1.1.0
-- Deployment Gate : PROD requires SOX dual approval (CHG0094127)
-- =============================================================================

  gc_pkg_name    CONSTANT VARCHAR2(30) := 'XXAP_INVOICE_UTILS';
  gc_pkg_version CONSTANT VARCHAR2(10) := '1.1.0';

  gc_ret_success CONSTANT VARCHAR2(1) := FND_API.G_RET_STS_SUCCESS;
  gc_ret_error   CONSTANT VARCHAR2(1) := FND_API.G_RET_STS_ERROR;
  gc_ret_unexp   CONSTANT VARCHAR2(1) := FND_API.G_RET_STS_UNEXP_ERROR;

  PROCEDURE validate_invoice (
    p_api_version    IN  NUMBER     DEFAULT 1.0,
    p_invoice_id     IN  NUMBER,
    p_org_id         IN  NUMBER,
    p_calling_module IN  VARCHAR2   DEFAULT NULL,
    x_return_status  OUT NOCOPY VARCHAR2,
    x_msg_count      OUT NOCOPY NUMBER,
    x_msg_data       OUT NOCOPY VARCHAR2
  );

  PROCEDURE validate_3way_match (
    p_invoice_id     IN  NUMBER,
    p_po_header_id   IN  NUMBER,
    p_tolerance_pct  IN  NUMBER    DEFAULT 5,
    x_return_status  OUT NOCOPY VARCHAR2,
    x_match_status   OUT NOCOPY VARCHAR2,
    x_variance_amt   OUT NOCOPY NUMBER
  );

  FUNCTION get_invoice_amount (
    p_invoice_id  IN  NUMBER,
    p_amount_type IN  VARCHAR2  DEFAULT 'TOTAL'
  ) RETURN NUMBER;

  PROCEDURE log_invoice_event (
    p_invoice_id  IN  NUMBER,
    p_event_type  IN  VARCHAR2,
    p_event_msg   IN  VARCHAR2,
    p_user_id     IN  NUMBER  DEFAULT FND_GLOBAL.USER_ID
  );

END XXAP_INVOICE_UTILS;
/
