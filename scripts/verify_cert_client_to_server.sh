#!/usr/bin/env bash
# =============================================================================
# verify_cert_client_to_server.sh
#
# Shell equivalent of:
#   roles/verify_cert_common/tasks/verify_cert_cluster_client_to_server.yml
#   (client-to-server scenario only)
#
# Run this ON the client node.
#
# Usage (read cert paths from gateway.conf):
#   ./verify_cert_client_to_server.sh \
#       --gateway-conf ~/.gateway.d/gateway.conf \
#       --server-ip 1.1.1.1 \
#       --server-port 50051 \
#       --service-name iagctl
#
# Usage (supply cert paths directly — no gateway.conf needed):
#   ./verify_cert_client_to_server.sh \
#       --server-ip 1.1.1.1 \
#       --ca-cert  /path/to/ca-bundle.crt \
#       --cert     /path/to/client.crt \
#       --key      /path/to/client.key
#
# Cert flags override whatever is found in gateway.conf when both are supplied.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Defaults — override with flags or edit here
# -----------------------------------------------------------------------------
GATEWAY_CONF="${HOME}/.gateway.d/gateway.conf"
SERVER_IP=""
SERVER_PORT="50051"
SERVICE_NAME="iagctl"
NODE_SECTION="client"
# Optional overrides — if set, skip parsing gateway.conf for these values
OPT_CA_CERT=""
OPT_CERT=""
OPT_KEY=""

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-conf)  GATEWAY_CONF="$2";  shift 2 ;;
    --server-ip)     SERVER_IP="$2";     shift 2 ;;
    --server-port)   SERVER_PORT="$2";   shift 2 ;;
    --service-name)  SERVICE_NAME="$2";  shift 2 ;;
    --ca-cert)       OPT_CA_CERT="$2";   shift 2 ;;
    --cert)          OPT_CERT="$2";      shift 2 ;;
    --key)           OPT_KEY="$2";       shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$SERVER_IP" ]]; then
  echo "ERROR: --server-ip is required"
  exit 1
fi

# gateway.conf is only required when cert paths aren't supplied directly
CONF_REQUIRED=true
[[ -n "$OPT_CA_CERT" && -n "$OPT_CERT" && -n "$OPT_KEY" ]] && CONF_REQUIRED=false

if [[ "$CONF_REQUIRED" == true && ! -f "$GATEWAY_CONF" ]]; then
  echo "ERROR: gateway.conf not found at: $GATEWAY_CONF"
  echo "       Either fix the path with --gateway-conf or supply --ca-cert, --cert, and --key directly."
  exit 1
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
PASS="✅ PASS"
FAIL="❌ FAIL"
WARN="⚠️  WARN"
SKIP="⏭ SKIPPED"
INFO="ℹ️  INFO"

RESULTS=()

record() {
  local check="$1"
  local expected="$2"
  local actual="$3"
  local status="$4"
  RESULTS+=("$status | $check")
  RESULTS+=("         Expected : $expected")
  RESULTS+=("         Actual   : $actual")
  RESULTS+=("------------------------------------------------------------")
}

section_value() {
  # Extract a key's value from a named INI section in gateway.conf.
  # Returns empty string safely when gateway.conf does not exist.
  local section="$1"
  local key="$2"
  [[ -f "$GATEWAY_CONF" ]] || { echo ""; return; }
  awk "/^\[$section\]/{f=1} f && /^\[/{if(!/^\[$section\]/) f=0} f && /^$key/" "$GATEWAY_CONF" 2>/dev/null || true
}

print_header() {
  echo "============================================================"
  echo "CLUSTER TLS — CLIENT → SERVER (gRPC mTLS) — CLIENT NODE"
  echo "============================================================"
}

# =============================================================================
# CHECK 1 — CA certificate file set in [application] section
# =============================================================================
CA_CONF_LINE=$(section_value "application" "ca_certificate_file")
CA_CERT_PATH=""
if [[ -n "$OPT_CA_CERT" ]]; then
  # CLI override — skip conf parsing for this value
  CA_CERT_PATH="$OPT_CA_CERT"
  record "CHECK 1 — [application] ca_certificate_file is set" \
         "ca_certificate_file = /path/to/ca-bundle.crt" \
         "supplied via --ca-cert: $CA_CERT_PATH" "$PASS"
elif [[ -n "$CA_CONF_LINE" ]]; then
  CA_CERT_PATH=$(echo "$CA_CONF_LINE" | cut -d= -f2- | tr -d " '\"")
  record "CHECK 1 — [application] ca_certificate_file is set" \
         "ca_certificate_file = /path/to/ca-bundle.crt" \
         "$CA_CONF_LINE" "$PASS"
else
  record "CHECK 1 — [application] ca_certificate_file is set" \
         "ca_certificate_file = /path/to/ca-bundle.crt" \
         "NOT FOUND" "$FAIL"
fi

# =============================================================================
# CHECK 2 — CA certificate file exists on disk
# =============================================================================
if [[ -n "$CA_CERT_PATH" ]]; then
  if [[ -f "$CA_CERT_PATH" ]]; then
    record "CHECK 2 — [application] ca_certificate_file exists on disk" \
           "File exists at $CA_CERT_PATH" "EXISTS" "$PASS"
  else
    record "CHECK 2 — [application] ca_certificate_file exists on disk" \
           "File exists at $CA_CERT_PATH" "NOT FOUND on disk" "$FAIL"
    CA_CERT_PATH=""
  fi
fi

# =============================================================================
# CHECK 3 — CA bundle cert count
# =============================================================================
if [[ -n "$CA_CERT_PATH" ]]; then
  CA_COUNT=$(grep -c "BEGIN CERTIFICATE" "$CA_CERT_PATH" 2>/dev/null || echo "0")
  if [[ "$CA_COUNT" -ge 2 ]]; then
    STATUS="$PASS"
  elif [[ "$CA_COUNT" -eq 1 ]]; then
    STATUS="$WARN — only root CA present, no intermediate (valid but less secure)"
  else
    STATUS="$FAIL — no certificates found in CA bundle"
  fi
  record "CHECK 3 — CA bundle cert count" \
         "At least 1 cert (root only is valid; 2 = root + intermediate)" \
         "${CA_COUNT} cert(s) found" "$STATUS"
fi

# =============================================================================
# CHECK 4 — CA cert has CA:TRUE
# =============================================================================
if [[ -n "$CA_CERT_PATH" ]]; then
  CA_CONSTRAINTS=$(openssl x509 -in "$CA_CERT_PATH" -noout -text 2>/dev/null | grep -A1 "CA:" || true)
  if echo "$CA_CONSTRAINTS" | grep -q "TRUE"; then
    record "CHECK 4 — CA cert has CA:TRUE (can sign other certs)" \
           "CA:TRUE" "$CA_CONSTRAINTS" "$PASS"
  else
    record "CHECK 4 — CA cert has CA:TRUE (can sign other certs)" \
           "CA:TRUE" "${CA_CONSTRAINTS:-NOT FOUND}" "$FAIL"
  fi
fi

# =============================================================================
# CHECK 5 — Last cert in CA bundle is self-signed root (subject hash == issuer hash)
# =============================================================================
if [[ -n "$CA_CERT_PATH" ]]; then
  SUBJECT_HASH=$(openssl x509 -in <(awk '/-----BEGIN CERTIFICATE-----/{c++} c==2{print}' "$CA_CERT_PATH") -noout -subject_hash 2>/dev/null || true)
  ISSUER_HASH=$(openssl x509  -in <(awk '/-----BEGIN CERTIFICATE-----/{c++} c==2{print}' "$CA_CERT_PATH") -noout -issuer_hash  2>/dev/null || true)
  if [[ -n "$SUBJECT_HASH" && "$SUBJECT_HASH" == "$ISSUER_HASH" ]]; then
    record "CHECK 5 — Last cert in CA bundle is self-signed root (subject hash == issuer hash)" \
           "Both hashes match" "subject=$SUBJECT_HASH issuer=$ISSUER_HASH" "$PASS"
  else
    record "CHECK 5 — Last cert in CA bundle is self-signed root (subject hash == issuer hash)" \
           "Both hashes match" "subject=${SUBJECT_HASH:-ERROR} issuer=${ISSUER_HASH:-ERROR}" "$FAIL"
  fi
fi

# =============================================================================
# CHECK 6 — use_tls in [client] section
# =============================================================================
NODE_USETLS=$(section_value "$NODE_SECTION" "use_tls")
TLS_ENABLED=false
if [[ -n "$OPT_CERT" && -n "$OPT_KEY" && -n "$OPT_CA_CERT" ]]; then
  # All cert paths supplied directly — assume TLS is enabled
  TLS_ENABLED=true
  record "CHECK 6 — [$NODE_SECTION] use_tls" "use_tls = true" \
         "assumed true (cert paths supplied via CLI flags)" "$PASS"
elif echo "$NODE_USETLS" | grep -q "true"; then
  TLS_ENABLED=true
  record "CHECK 6 — [$NODE_SECTION] use_tls" "use_tls = true" "$NODE_USETLS" "$PASS"
else
  record "CHECK 6 — [$NODE_SECTION] use_tls" "use_tls = true" \
         "${NODE_USETLS:-NOT FOUND}" "$FAIL — TLS disabled, skipping cert checks"
fi

# =============================================================================
# CHECK 7 — certificate_file set in [client] section
# =============================================================================
NODE_CERT_PATH=""
if [[ "$TLS_ENABLED" == true ]]; then
  if [[ -n "$OPT_CERT" ]]; then
    NODE_CERT_PATH="$OPT_CERT"
    record "CHECK 7 — [$NODE_SECTION] certificate_file is set" \
           "certificate_file = /path/to/cert" \
           "supplied via --cert: $NODE_CERT_PATH" "$PASS"
  else
    NODE_CERT_CONF=$(section_value "$NODE_SECTION" "certificate_file")
    if [[ -n "$NODE_CERT_CONF" ]]; then
      NODE_CERT_PATH=$(echo "$NODE_CERT_CONF" | cut -d= -f2- | tr -d " '\"")
      record "CHECK 7 — [$NODE_SECTION] certificate_file is set" \
             "certificate_file = /path/to/cert" "$NODE_CERT_CONF" "$PASS"
    else
      record "CHECK 7 — [$NODE_SECTION] certificate_file is set" \
             "certificate_file = /path/to/cert" "NOT FOUND" "$FAIL"
    fi
  fi
else
  record "CHECK 7 — [$NODE_SECTION] certificate_file is set" \
         "certificate_file = /path/to/cert" "N/A" "$SKIP — TLS disabled"
fi

# =============================================================================
# CHECK 8 — certificate_file exists on disk
# =============================================================================
if [[ "$TLS_ENABLED" == true && -n "$NODE_CERT_PATH" ]]; then
  if [[ -f "$NODE_CERT_PATH" ]]; then
    record "CHECK 8 — [$NODE_SECTION] certificate_file exists on disk" \
           "File exists at $NODE_CERT_PATH" "EXISTS" "$PASS"
  else
    record "CHECK 8 — [$NODE_SECTION] certificate_file exists on disk" \
           "File exists at $NODE_CERT_PATH" "NOT FOUND on disk" "$FAIL"
    NODE_CERT_PATH=""
  fi
fi

# =============================================================================
# CHECK 9 — private_key_file set in [client] section
# =============================================================================
NODE_KEY_PATH=""
if [[ "$TLS_ENABLED" == true ]]; then
  if [[ -n "$OPT_KEY" ]]; then
    NODE_KEY_PATH="$OPT_KEY"
    record "CHECK 9 — [$NODE_SECTION] private_key_file is set" \
           "private_key_file = /path/to/key" \
           "supplied via --key: $NODE_KEY_PATH" "$PASS"
  else
    NODE_KEY_CONF=$(section_value "$NODE_SECTION" "private_key_file")
    if [[ -n "$NODE_KEY_CONF" ]]; then
      NODE_KEY_PATH=$(echo "$NODE_KEY_CONF" | cut -d= -f2- | tr -d " '\"")
      record "CHECK 9 — [$NODE_SECTION] private_key_file is set" \
             "private_key_file = /path/to/key" "$NODE_KEY_CONF" "$PASS"
    else
      record "CHECK 9 — [$NODE_SECTION] private_key_file is set" \
             "private_key_file = /path/to/key" "NOT FOUND" "$FAIL"
    fi
  fi
else
  record "CHECK 9 — [$NODE_SECTION] private_key_file is set" \
         "private_key_file = /path/to/key" "N/A" "$SKIP — TLS disabled"
fi

# =============================================================================
# CHECK 10 — private_key_file exists on disk
# =============================================================================
if [[ "$TLS_ENABLED" == true && -n "$NODE_KEY_PATH" ]]; then
  if [[ -f "$NODE_KEY_PATH" ]]; then
    record "CHECK 10 — [$NODE_SECTION] private_key_file exists on disk" \
           "File exists at $NODE_KEY_PATH" "EXISTS" "$PASS"
  else
    record "CHECK 10 — [$NODE_SECTION] private_key_file exists on disk" \
           "File exists at $NODE_KEY_PATH" "NOT FOUND on disk" "$FAIL"
    NODE_KEY_PATH=""
  fi
fi

# =============================================================================
# CHECK 11 — cert and key are a matched pair
# =============================================================================
EKU_VALID=false
if [[ "$TLS_ENABLED" == true && -n "$NODE_CERT_PATH" && -n "$NODE_KEY_PATH" ]]; then
  CERT_MOD=$(openssl x509 -noout -modulus -in "$NODE_CERT_PATH" 2>/dev/null | md5sum || echo "ERROR")
  KEY_MOD=$(openssl rsa   -noout -modulus -in "$NODE_KEY_PATH"  2>/dev/null | md5sum || echo "ERROR")
  if [[ "$CERT_MOD" == "$KEY_MOD" ]]; then
    record "CHECK 11 — [$NODE_SECTION] cert and key are a matched pair" \
           "Matching md5 hashes" "cert=$CERT_MOD key=$KEY_MOD" "$PASS"
  else
    record "CHECK 11 — [$NODE_SECTION] cert and key are a matched pair" \
           "Matching md5 hashes" "cert=$CERT_MOD key=$KEY_MOD" "$FAIL"
  fi
fi

# =============================================================================
# CHECK 12 — cert not expired
# =============================================================================
if [[ "$TLS_ENABLED" == true && -n "$NODE_CERT_PATH" ]]; then
  if openssl x509 -in "$NODE_CERT_PATH" -noout -checkend 0 2>/dev/null; then
    DATES=$(openssl x509 -in "$NODE_CERT_PATH" -noout -dates 2>/dev/null)
    record "CHECK 12 — [$NODE_SECTION] cert is not expired" \
           "Certificate is valid" "$DATES" "$PASS"
  else
    record "CHECK 12 — [$NODE_SECTION] cert is not expired" \
           "Certificate is valid" "EXPIRED" "$FAIL"
  fi
fi

# =============================================================================
# CHECK 13 — cert days remaining
# =============================================================================
if [[ "$TLS_ENABLED" == true && -n "$NODE_CERT_PATH" ]]; then
  END_DATE=$(openssl x509 -enddate -noout -in "$NODE_CERT_PATH" 2>/dev/null | cut -d= -f2)
  DAYS_LEFT=$(( ( $(date -d "$END_DATE" +%s) - $(date +%s) ) / 86400 ))
  if [[ "$DAYS_LEFT" -gt 30 ]]; then
    STATUS="$PASS"
  elif [[ "$DAYS_LEFT" -gt 0 ]]; then
    STATUS="$WARN — expiring within 30 days"
  else
    STATUS="$FAIL — expired"
  fi
  record "CHECK 13 — [$NODE_SECTION] cert days remaining until expiry" \
         "More than 30 days remaining" "${DAYS_LEFT} days remaining" "$STATUS"
fi

# =============================================================================
# CHECK 14 — cert is not self-signed leaf (subject != issuer)
# =============================================================================
if [[ "$TLS_ENABLED" == true && -n "$NODE_CERT_PATH" ]]; then
  SUBJECT=$(openssl x509 -in "$NODE_CERT_PATH" -noout -subject 2>/dev/null)
  ISSUER=$(openssl  x509 -in "$NODE_CERT_PATH" -noout -issuer  2>/dev/null)
  if [[ "$SUBJECT" != "$ISSUER" ]]; then
    record "CHECK 14 — [$NODE_SECTION] cert is not a self-signed leaf (subject != issuer)" \
           "subject != issuer (CA-signed)" "subject: $SUBJECT | issuer: $ISSUER" "$PASS"
  else
    record "CHECK 14 — [$NODE_SECTION] cert is not a self-signed leaf (subject != issuer)" \
           "subject != issuer (CA-signed)" "SELF-SIGNED" "$FAIL — self-signed leaf rejected by cluster TLS"
  fi
fi

# =============================================================================
# CHECK 15 — cert signed by CA
# =============================================================================
if [[ "$TLS_ENABLED" == true && -n "$CA_CERT_PATH" && -n "$NODE_CERT_PATH" ]]; then
  VERIFY_OUT=$(openssl verify -CAfile "$CA_CERT_PATH" "$NODE_CERT_PATH" 2>&1 || true)
  if echo "$VERIFY_OUT" | grep -q "OK"; then
    record "CHECK 15 — [$NODE_SECTION] cert is signed by CA" "OK" "$VERIFY_OUT" "$PASS"
  else
    record "CHECK 15 — [$NODE_SECTION] cert is signed by CA" "OK" "$VERIFY_OUT" "$FAIL"
  fi
fi

# =============================================================================
# CHECK 16 — extendedKeyUsage has serverAuth + clientAuth
# =============================================================================
if [[ "$TLS_ENABLED" == true && -n "$NODE_CERT_PATH" ]]; then
  EKU=$(openssl x509 -in "$NODE_CERT_PATH" -noout -text 2>/dev/null | grep -A3 "Extended Key Usage" || true)
  if echo "$EKU" | grep -q "Server Authentication" && echo "$EKU" | grep -q "Client Authentication"; then
    EKU_VALID=true
    record "CHECK 16 — [$NODE_SECTION] cert has both serverAuth and clientAuth in extendedKeyUsage" \
           "TLS Web Server Authentication, TLS Web Client Authentication" "$EKU" "$PASS"
  elif [[ -z "$EKU" ]]; then
    record "CHECK 16 — [$NODE_SECTION] cert has both serverAuth and clientAuth in extendedKeyUsage" \
           "TLS Web Server Authentication, TLS Web Client Authentication" "NOT SET" \
           "$WARN — extendedKeyUsage not set, relying on defaults"
  else
    record "CHECK 16 — [$NODE_SECTION] cert has both serverAuth and clientAuth in extendedKeyUsage" \
           "TLS Web Server Authentication, TLS Web Client Authentication" "$EKU" \
           "$FAIL — missing clientAuth or serverAuth, mTLS handshake will be rejected"
  fi
fi

# =============================================================================
# CHECK 19 — no_proxy/NO_PROXY set in service environment
# =============================================================================
PROXY_ENV=$(systemctl show "$SERVICE_NAME" 2>/dev/null | grep Environ | grep -oE "(no_proxy|NO_PROXY)=[^ ]*" || true)
if [[ -n "$PROXY_ENV" ]]; then
  record "CHECK 19 — no_proxy/NO_PROXY is set in systemd service" \
         "no_proxy and NO_PROXY env vars present" "$PROXY_ENV" "$PASS"
else
  record "CHECK 19 — no_proxy/NO_PROXY is set in systemd service" \
         "no_proxy and NO_PROXY env vars present" "NOT SET" \
         "$WARN — no proxy exclusions set, all traffic may go through proxy"
fi

# =============================================================================
# CHECK 20 — server IP is in no_proxy
# =============================================================================
if echo "$PROXY_ENV" | grep -q "$SERVER_IP"; then
  record "CHECK 20 — Server private IP $SERVER_IP is in no_proxy" \
         "$SERVER_IP present in no_proxy" "$PROXY_ENV" "$PASS"
else
  record "CHECK 20 — Server private IP $SERVER_IP is in no_proxy" \
         "$SERVER_IP present in no_proxy" "${PROXY_ENV:-NOT SET}" \
         "$FAIL — server IP not in no_proxy, gRPC will route through proxy"
fi

# =============================================================================
# CHECK 22 — server enforces mTLS (reject without client cert)
# =============================================================================
if [[ "$TLS_ENABLED" == true && "$EKU_VALID" == true && -n "$CA_CERT_PATH" ]]; then
  MTLS_OUT=$(echo Q | openssl s_client \
    -connect "${SERVER_IP}:${SERVER_PORT}" \
    -CAfile "$CA_CERT_PATH" \
    </dev/null 2>&1 | grep -E "alert|handshake failure|error" || true)
  if [[ -n "$MTLS_OUT" ]]; then
    record "CHECK 22 — Server enforces mTLS (rejects connection without client cert)" \
           "Connection rejected — alert or handshake failure" "$MTLS_OUT" "$PASS"
  else
    record "CHECK 22 — Server enforces mTLS (rejects connection without client cert)" \
           "Connection rejected — alert or handshake failure" "NO OUTPUT" \
           "$FAIL — server accepted connection without client cert"
  fi
else
  record "CHECK 22 — Server enforces mTLS (rejects connection without client cert)" \
         "Connection rejected — alert or handshake failure" "N/A" \
         "$SKIP — EKU invalid or TLS disabled"
fi

# =============================================================================
# CHECK 23 — service running and GATEWAY vars in process environment
# =============================================================================
SVC_PID=$(systemctl show "$SERVICE_NAME" --property=MainPID 2>/dev/null | cut -d= -f2 || true)
PROC_ENV=""
if [[ -n "$SVC_PID" && "$SVC_PID" != "0" && -f "/proc/${SVC_PID}/environ" ]]; then
  PROC_ENV=$(cat "/proc/${SVC_PID}/environ" | tr '\0' '\n' | grep -E "GATEWAY_APPLICATION_CA|GATEWAY_CLIENT" || true)
fi
if [[ -n "$PROC_ENV" ]]; then
  record "CHECK 23 — Service is running and GATEWAY vars present in process environment" \
         "GATEWAY vars visible in /proc/PID/environ" "$PROC_ENV" "$PASS"
else
  record "CHECK 23 — Service is running and GATEWAY vars present in process environment" \
         "GATEWAY vars visible in /proc/PID/environ" \
         "NOT FOUND — service may be using gateway.conf only (expected)" \
         "$INFO — vars not in env, confirm gateway.conf is used"
fi

# =============================================================================
# CHECK 24 — server host resolves from client
# =============================================================================
if [[ "$TLS_ENABLED" == true ]]; then
  RESOLVE_OUT=$(getent ahosts "$SERVER_IP" 2>&1 || true)
  if [[ -n "$RESOLVE_OUT" ]]; then
    record "CHECK 24 — Server host resolves from client ($SERVER_IP)" \
           "Host resolves successfully" "$RESOLVE_OUT" "$PASS"
  else
    record "CHECK 24 — Server host resolves from client ($SERVER_IP)" \
           "Host resolves successfully" "FAILED TO RESOLVE" "$FAIL"
  fi
fi

# =============================================================================
# CHECK 25 — TCP connectivity CLIENT → SERVER
# =============================================================================
if [[ "$TLS_ENABLED" == true ]]; then
  if timeout 5 bash -c "echo > /dev/tcp/${SERVER_IP}/${SERVER_PORT}" 2>/dev/null; then
    record "CHECK 25 — TCP connectivity CLIENT → SERVER (${SERVER_IP}:${SERVER_PORT})" \
           "Port reachable within 5 seconds" "REACHABLE" "$PASS"
  else
    record "CHECK 25 — TCP connectivity CLIENT → SERVER (${SERVER_IP}:${SERVER_PORT})" \
           "Port reachable within 5 seconds" "UNREACHABLE — check security groups" "$FAIL"
  fi
fi

# =============================================================================
# CHECK 26 — TLS handshake with IP verification CLIENT → SERVER
# =============================================================================
if [[ "$TLS_ENABLED" == true && "$EKU_VALID" == true && -n "$NODE_CERT_PATH" ]]; then
  HANDSHAKE_OUT=$(openssl s_client \
    -connect "${SERVER_IP}:${SERVER_PORT}" \
    -verify_ip "$SERVER_IP" \
    -verify_return_error \
    -cert "$NODE_CERT_PATH" \
    -key  "$NODE_KEY_PATH" \
    -CAfile "$CA_CERT_PATH" \
    -showcerts </dev/null 2>&1 || true)
  VERIFY_CODE=$(echo "$HANDSHAKE_OUT" | grep "Verify return code" || echo "No verify return code found")
  if echo "$HANDSHAKE_OUT" | grep -q "Verify return code: 0"; then
    record "CHECK 26 — TLS handshake with IP verification CLIENT → SERVER ($SERVER_IP)" \
           "Verify return code: 0 (ok)" "$VERIFY_CODE" "$PASS"
  else
    record "CHECK 26 — TLS handshake with IP verification CLIENT → SERVER ($SERVER_IP)" \
           "Verify return code: 0 (ok)" "$VERIFY_CODE" "$FAIL"
  fi
else
  record "CHECK 26 — TLS handshake with IP verification CLIENT → SERVER ($SERVER_IP)" \
         "Verify return code: 0 (ok)" "N/A" "$SKIP — EKU invalid or TLS disabled"
fi

# =============================================================================
# Summary
# =============================================================================
print_header
for line in "${RESULTS[@]}"; do
  echo "$line"
done
echo "============================================================"

FAIL_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -c "❌ FAIL" || true)
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "Overall Status: PASSED ✓"
else
  echo "Overall Status: FAILED ✗ ($FAIL_COUNT failure(s))"
fi
echo "============================================================"
