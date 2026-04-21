SELECT * FROM (

    -- 1. GENETATION INVOICE (Text Format)
    SELECT 
        'INVOICE' as doc_type,
        inv.invoice_number || '.txt' as filename,
        'INVOICE NO: ' || inv.invoice_number || CHR(10) ||
        'DATE      : ' || inv.invoice_date || CHR(10) ||
        'STATUS    : ' || inv.status || CHR(10) ||
        '-------------------------------------------------------------' || CHR(10) ||
        'FROM: ' || org.legal_name || CHR(10) ||
        '      ' || org.address_legal || CHR(10) ||
        'TO  : ' || part.legal_name || CHR(10) ||
        '      ' || COALESCE(part.address_physical, part.city) || CHR(10) ||
        '-------------------------------------------------------------' || CHR(10) ||
        'ITEM DESCRIPTION                       QTY     PRICE    TOTAL' || CHR(10) ||
        '-------------------------------------------------------------' || CHR(10) ||
        (
            SELECT STRING_AGG(
                RPAD(LEFT(COALESCE(p.name_en, ii.description), 35), 35) || ' ' || 
                LPAD(ii.quantity::text, 7) || ' ' || 
                LPAD(ii.unit_price::text, 9) || ' ' || 
                LPAD(ii.total_price::text, 9), 
                CHR(10)
            )
            FROM invoice_items ii 
            LEFT JOIN products p ON ii.product_id = p.id
            WHERE ii.invoice_id = inv.id
        ) || CHR(10) ||
        '-------------------------------------------------------------' || CHR(10) ||
        'TOTAL AMOUNT: ' || inv.amount_total || ' ' || inv.currency_code || CHR(10) ||
        'PAYMENT TERMS: ' || COALESCE(part.payment_terms, 'DUE ON RECEIPT') || CHR(10) ||
        'BANK: ' || (SELECT bank_name FROM bank_accounts ba WHERE ba.organization_id = inv.organization_id AND ba.currency_code = inv.currency_code LIMIT 1) || CHR(10) ||
        'SWIFT: ' || (SELECT swift_bic FROM bank_accounts ba WHERE ba.organization_id = inv.organization_id AND ba.currency_code = inv.currency_code LIMIT 1)
        as document_content
    FROM invoices inv
    JOIN organizations org ON inv.organization_id = org.id
    JOIN partners part ON inv.partner_id = part.id

    UNION ALL

    -- 2. GENERATION SWIFT MT103 (Payments)
    SELECT 
        'PAYMENT_SWIFT' as doc_type,
        'MT103_' || p.id || '.txt' as filename,
        '{1:F01' || ba.swift_bic || 'AXXX0000000000}' || CHR(10) ||
        '{2:O103' || TO_CHAR(p.payment_date, 'HH24MI') || LEFT(org.legal_name, 10) || '...}' || CHR(10) ||
        '{4:' || CHR(10) ||
        ':20:' || COALESCE(p.transaction_ref, 'NONREF') || CHR(10) ||
        ':23B:CRED' || CHR(10) ||
        ':32A:' || TO_CHAR(p.payment_date, 'YYMMDD') || p.currency_code || REPLACE(p.amount::text, '.', ',') || CHR(10) ||
        ':50K:' || part.legal_name || CHR(10) ||
        '     ' || COALESCE(part.address_physical, 'ADDRESS UNKNOWN') || CHR(10) ||
        ':59:/' || ba.account_number || CHR(10) ||
        '     ' || org.legal_name || CHR(10) ||
        ':70:INV REF ' || (SELECT invoice_number FROM invoices WHERE id = p.invoice_id) || CHR(10) ||
        '     ' || COALESCE(p.notes, 'PAYMENT') || CHR(10) ||
        ':71A:SHA' || CHR(10) ||
        '-}'
        as document_content
    FROM payments p
    JOIN bank_accounts ba ON p.bank_account_id = ba.id
    JOIN organizations org ON ba.organization_id = org.id
    LEFT JOIN invoices inv ON p.invoice_id = inv.id
    LEFT JOIN partners part ON inv.partner_id = part.id
    WHERE p.method = 'SWIFT'

    UNION ALL

    -- 3. BILL OF LADING GENERATION / AWB (Logistics)
    SELECT 
        'LOGISTICS' as doc_type,
        CASE WHEN s.transport_mode = 'AIR' THEN 'AWB_' ELSE 'BL_' END || s.tracking_number || '.txt' as filename,
        'DOCUMENT: ' || CASE WHEN s.transport_mode = 'AIR' THEN 'AIR WAYBILL (AWB)' ELSE 'BILL OF LADING (BOL)' END || CHR(10) ||
        'NUMBER  : ' || COALESCE(s.bol_number, s.tracking_number) || CHR(10) ||
        'CARRIER : ' || part.legal_name || CHR(10) ||
        'VESSEL/FLIGHT: ' || COALESCE(s.vessel_flight_no, 'TBA') || CHR(10) ||
        '=============================================================' || CHR(10) ||
        'SHIPPER:' || CHR(10) ||
        'GEORGIAN FRESH EXPORT LLC' || CHR(10) ||
        'BATUMI, GEORGIA' || CHR(10) ||
        '-------------------------------------------------------------' || CHR(10) ||
        'CONSIGNEE:' || CHR(10) ||
        cust.legal_name || CHR(10) ||
        cust.city || ', ' || cust.country_code || CHR(10) ||
        '-------------------------------------------------------------' || CHR(10) ||
        'PORT OF LOADING: ' || s.origin_port || '   ETD: ' || s.etd_date || CHR(10) ||
        'PORT OF DISCH. : ' || s.destination_port || '   ETA: ' || COALESCE(s.eta_date::text, 'TBA') || CHR(10) ||
        '-------------------------------------------------------------' || CHR(10) ||
        'CONTAINER/REF   PKGS    DESCRIPTION             GROSS WT' || CHR(10) ||
        RPAD(s.tracking_number, 16) || '20 PLT  FRESH PRODUCE           22,000 KG' || CHR(10) ||
        '                        HS CODE: 0805.21' || CHR(10) ||
        '                        TEMP: +4.0C' || CHR(10) ||
        '=============================================================' || CHR(10) ||
        'FREIGHT: ' || CASE WHEN o.incoterms IN ('CIF', 'DDP') THEN 'PREPAID' ELSE 'COLLECT' END || CHR(10) ||
        'ISSUED AT: ' || s.origin_port || CHR(10) ||
        'SIGNED: AS AGENT FOR THE CARRIER'
        as document_content
    FROM shipments s
    JOIN partners part ON s.carrier_id = part.id
    JOIN orders o ON s.order_id = o.id
    JOIN partners cust ON o.customer_id = cust.id

    UNION ALL

    -- 4. TRADE FINACIAL GENERATION (LC / Guarantee / Collection)
    SELECT
        'TRADE_FINANCE' as doc_type,
        ti.document_number || '.txt' as filename,
        '{1:F01' || REPLACE(ti.issuing_bank, ' ', '') || 'XXXX}' || CHR(10) ||
        '{2:I' || CASE 
            WHEN ti.type LIKE 'LC%' THEN '700' 
            WHEN ti.type = 'BANK_GUARANTEE' THEN '760' 
            ELSE '400' 
        END || REPLACE(ti.advising_bank, ' ', '') || 'XXXX}' || CHR(10) ||
        '{4:' || CHR(10) ||
        ':20:' || ti.document_number || CHR(10) ||
        ':31C:' || TO_CHAR(ti.issue_date, 'YYMMDD') || CHR(10) ||
        ':40A:IRREVOCABLE' || CHR(10) ||
        ':32B:' || ti.currency_code || ti.amount || CHR(10) ||
        ':50:APPLICANT: ' || (SELECT legal_name FROM organizations WHERE id = ti.organization_id) || CHR(10) ||
        ':59:BENEFICIARY: ' || 'COUNTERPARTY NAME' || CHR(10) ||
        ':41A:AVAILABLE WITH... BY...' || CHR(10) ||
        ':45A:DESCRIPTION OF GOODS:' || CHR(10) ||
        '     FRESH FRUITS AS PER PROFORMA INV.' || CHR(10) ||
        '-}'
        as document_content
    FROM trade_instruments ti

) AS all_docs
ORDER BY doc_type, filename;
