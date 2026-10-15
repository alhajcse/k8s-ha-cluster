# Step 1 — Create a Local CA on Your Laptop

> **Working directory:** `~/Documents/k8s-ha-cluster`  
> **Purpose:** Build a private Certificate Authority (CA) and issue a TLS certificate for `whoami.lab.local` to be used with Traefik Ingress.

---

## Prepare the TLS Directory

```bash
mkdir -p tls
chmod 700 tls
cd tls
```

**Why?**  
Keeps all certificate files isolated and restricts directory access to the owner only.

---

## 1.1 — Create the CA Private Key

```bash
openssl genrsa -out lab-ca.key 4096
chmod 600 lab-ca.key
```

**Why?**  
This private key will sign all TLS certificates in your lab. It must stay on your laptop only and **never** be copied into the Kubernetes cluster.

---

## 1.2 — Create the CA Certificate

```bash
openssl req -x509 -new -nodes \
  -key lab-ca.key \
  -sha256 \
  -days 3650 \
  -out lab-ca.crt \
  -subj "/CN=K8s-Lab-Root-CA"
```

**Result:** A self-signed public certificate for your **Local Certificate Authority**, valid for 10 years.

---

## 1.3 — Create the Application Private Key

```bash
openssl genrsa -out whoami.lab.local.key 2048
chmod 600 whoami.lab.local.key
```

**Why?**  
This is the private key that will be paired with the application certificate.

---

## 1.4 — Create the Certificate Signing Request (CSR)

```bash
openssl req -new \
  -key whoami.lab.local.key \
  -out whoami.lab.local.csr \
  -subj "/CN=whoami.lab.local"
```

### Add Subject Alternative Name (SAN)

> A modern browser will reject a certificate that only has a CN — the hostname **must** be in the SAN extension.

Create `whoami.ext`:

```bash
cat > whoami.ext <<'EOF'
subjectAltName = DNS:whoami.lab.local
extendedKeyUsage = serverAuth
keyUsage = critical,digitalSignature,keyEncipherment
EOF
```

| Extension | Purpose |
|-----------|---------|
| `subjectAltName` | Binds the hostname to the certificate |
| `extendedKeyUsage = serverAuth` | Allows use for TLS server authentication |
| `keyUsage` | Enables key encipherment & digital signature |

---

## 1.5 — Sign the Application Certificate with the Local CA

```bash
openssl x509 -req \
  -in whoami.lab.local.csr \
  -CA lab-ca.crt \
  -CAkey lab-ca.key \
  -CAcreateserial \
  -out whoami.lab.local.crt \
  -days 365 \
  -sha256 \
  -extfile whoami.ext
```

**Result:** A signed certificate valid for **365 days**, issued by `K8s-Lab-Root-CA`.

---

## 1.6 — Verify the Certificate

### Verify chain of trust

```bash
openssl verify \
  -CAfile lab-ca.crt \
  whoami.lab.local.crt
```

**Expected output:**

```
whoami.lab.local.crt: OK
```

### Inspect certificate details

```bash
openssl x509 -in whoami.lab.local.crt \
  -noout -subject -issuer -dates -ext subjectAltName
```

**Expected output:**

```
subject=CN = whoami.lab.local
issuer=CN = K8s-Lab-Root-CA
notBefore=...
notAfter=...
X509v3 Subject Alternative Name:
    DNS:whoami.lab.local
```

---

##  Security — Very Important

| File | Sensitivity | Where to Keep It |
|------|-------------|------------------|
| `lab-ca.key` | 🔴 **CRITICAL** | Laptop only — never copy anywhere |
| `lab-ca.crt` | 🟢 Public | Used to trust the CA on clients |
| `whoami.lab.local.key` | 🔴 **CRITICAL** | Only inside Kubernetes TLS Secret |
| `whoami.lab.local.crt` | 🟡 Public | Bundled with key in TLS Secret |
| `tls/` directory | 🔴 **CRITICAL** | Must **never** be committed to Git |

---

## Prevent Accidental Commit

Add the following entry to `.gitignore` at the repository root:

```gitignore
tls/
```

>  Before adding this line, make sure **no private key is already tracked** in the repo:

```bash
git ls-files tls/
# Expected: (no output)
```

If it returns any file, remove it from tracking first:

```bash
git rm --cached tls/<file>
git commit -m "Remove accidentally tracked TLS files"
```

---

## File Inventory After This Step

```text
~/Documents/k8s-ha-cluster/tls/
├── lab-ca.key              ← CA private key (KEEP SECRET)
├── lab-ca.crt              ← CA public certificate
├── lab-ca.srl              ← CA serial number file
├── whoami.lab.local.key    ← App private key (KEEP SECRET)
├── whoami.lab.local.csr    ← Certificate signing request
├── whoami.lab.local.crt    ← Signed app certificate
└── whoami.ext              ← SAN / key usage extension file
```

---

## Next Steps

1. **Create a Kubernetes TLS Secret** from the app key and certificate:

   ```bash
   kubectl create secret tls whoami-tls \
     --cert=tls/whoami.lab.local.crt \
     --key=tls/whoami.lab.local.key \
     -n demo
   ```

2. **Reference the secret in the Ingress:**

   ```yaml
   spec:
     tls:
       - hosts:
           - whoami.lab.local
         secretName: whoami-tls
   ```

3. **Trust the CA on your laptop** so browsers accept the certificate:

   - **Linux:** copy `lab-ca.crt` to `/usr/local/share/ca-certificates/` and run `sudo update-ca-certificates`
   - **macOS:** `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain lab-ca.crt`
   - **Windows:** import into `Trusted Root Certification Authorities` via `certmgr.msc`

4. **Add the hostname to `/etc/hosts`:**

   ```bash
   echo "<haproxy-or-ingress-ip> whoami.lab.local" | sudo tee -a /etc/hosts
   ```

---


# Step 2–5 — Deploy TLS Certificate to Cluster and Enable HTTPS

> **Assumption:** You completed **Step 1** and have `whoami.lab.local.crt` and `whoami.lab.local.key` in `~/Documents/k8s-ha-cluster/tls/` on your laptop.

---

##  Step 2 — Send the Certificate from Laptop to Server

From your laptop terminal, inside `~/Documents/k8s-ha-cluster/tls`:

```bash
scp whoami.lab.local.crt \
    whoami.lab.local.key \
    vm@10.70.16.237:/tmp/
```

**What is being transferred:**
-  Application certificate (`whoami.lab.local.crt`)
- Application private key (`whoami.lab.local.key`)

**What is NOT transferred:**
- `lab-ca.key` — CA private key must **never** leave your laptop
- `lab-ca.crt` — only needed on clients that trust the CA

---

## Step 3 — Create the TLS Secret on the Server

SSH into the server:

```bash
ssh vm@10.70.16.237
```

Then create the Secret in the `demo` namespace:

```bash
kubectl create secret tls whoami-tls \
  --namespace demo \
  --cert=/tmp/whoami.lab.local.crt \
  --key=/tmp/whoami.lab.local.key \
  --dry-run=client -o yaml |
kubectl apply -f -
```

### Why `--dry-run=client -o yaml | kubectl apply -f -`?

- `--dry-run=client` — generates the Secret YAML **locally** without sending to the API server.
- `-o yaml` — prints it as YAML.
- `kubectl apply -f -` — applies it, making the operation **idempotent** (safe to re-run).

### Verify the Secret

```bash
kubectl get secret whoami-tls -n demo
```

**Expected output:**

```text
NAME         TYPE                DATA   AGE
whoami-tls   kubernetes.io/tls   2      ...
```

 **Success criteria:** `TYPE` must be `kubernetes.io/tls`.

### Confirm the Secret contents

```bash
kubectl describe secret whoami-tls -n demo
```

You should see two keys: `tls.crt` and `tls.key`.

###  Clean up the temporary files

```bash
rm -f /tmp/whoami.lab.local.key \
      /tmp/whoami.lab.local.crt
```

**Why?** The private key should not linger in `/tmp` longer than necessary.

---

##  Step 4 — Add HTTPS to the Ingress

### 4.1 — Back up the current Ingress

```bash
kubectl get ingress whoami -n demo -o yaml \
  > /tmp/whoami-ingress-backup.yaml
```

**Why?** So you can restore the Ingress if the patch causes an issue.

### 4.2 — Patch the Ingress with a TLS section

```bash
kubectl patch ingress whoami -n demo --type=merge \
  -p '{"spec":{"tls":[{"hosts":["whoami.lab.local"],"secretName":"whoami-tls"}]}}'
```

**What this does:** adds a `spec.tls` block pointing to the `whoami-tls` Secret, enabling HTTPS for the `whoami.lab.local` host.

### 4.3 — Verify the Ingress

```bash
kubectl describe ingress whoami -n demo
```

**Expected output (partial):**

```text
Name:             whoami
Namespace:        demo
...
TLS:
  whoami-tls terminates whoami.lab.local
Rules:
  Host               Path  Backends
  ----               ----  --------
  whoami.lab.local
                     /     whoami:80 (...)
```

You should see `whoami.lab.local` and `whoami-tls` in the TLS section.

---

##  Step 5 — Test HTTPS

###  Where to run the test?

> **Recommendation:** Run the test from your **laptop**, not from the server.

**Reason:** The `--cacert` flag points to `lab-ca.crt`, which lives on your laptop. Copying the CA to the server as a public certificate would work, but testing from your laptop is simpler and matches the real-world client scenario.

### From your laptop

In `~/Documents/k8s-ha-cluster/tls`:

```bash
curl -v \
  --cacert lab-ca.crt \
  --resolve whoami.lab.local:30443:10.70.16.240 \
  https://whoami.lab.local:30443/
```

### What each flag does

| Flag | Purpose |
|------|---------|
| `--cacert lab-ca.crt` | Tells curl to trust your Local CA |
| `--resolve whoami.lab.local:30443:10.70.16.240` | Maps the hostname to worker-01 IP **without** editing `/etc/hosts` |
| `https://whoami.lab.local:30443/` | Requests the HTTPS endpoint on the NodePort |

### Expected output (partial)

```text
* Connected to whoami.lab.local (10.70.16.240) port 30443
* TLS 1.3 connection using TLS_AES_256_GCM_SHA384
* Server certificate:
*  subject: CN=whoami.lab.local
*  issuer: CN=K8s-Lab-Root-CA
*  SSL certificate verify ok.
> GET / HTTP/2
< HTTP/2 200
Hostname: whoami-f98576c84-hhl2b
X-Forwarded-Proto: https
```

 **Success indicators:**
- `SSL certificate verify ok`
- `HTTP/2 200`
- `X-Forwarded-Proto: https` — Traefik correctly identified the request as HTTPS

### Test the second worker (optional)

```bash
curl -v \
  --cacert lab-ca.crt \
  --resolve whoami.lab.local:30443:10.70.16.241 \
  https://whoami.lab.local:30443/
```

Both workers should serve HTTPS correctly.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SSL certificate problem: unable to get local issuer certificate` | `--cacert` missing or wrong file | Point to `lab-ca.crt` |
| `certificate is not valid for 'whoami.lab.local'` | SAN missing in cert | Re-issue cert with `subjectAltName = DNS:whoami.lab.local` |
| `Connection refused` on 30443 | Traefik not listening on HTTPS NodePort | Verify `kubectl get svc -n traefik` shows `30443` |
| `404 page not found` | Ingress host mismatch | Check `kubectl get ingress -n demo -o yaml` |
| `502 Bad Gateway` | Backend Pod not Ready | `kubectl get pods -n demo` |
| Browser still warns | CA not trusted on OS/browser | Import `lab-ca.crt` into Trusted Root store |
| `curl` works but browser does not | `/etc/hosts` not set | Add `10.70.16.240 whoami.lab.local` |

---



##  Next Steps

1. **Trust the CA system-wide** so browsers accept the certificate without warnings:
   - **Linux:** `sudo cp tls/lab-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`
   - **macOS:** `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain tls/lab-ca.crt`
   - **Windows:** `certmgr.msc` → Trusted Root Certification Authorities → Import

2. **Add `/etc/hosts` entry** for the browser test:

   ```bash
   echo "10.70.16.240 whoami.lab.local" | sudo tee -a /etc/hosts
   ```

3. **Automate certificate renewal** with **cert-manager + Let's Encrypt** for production.

4. **Add HTTPS redirect** so HTTP requests auto-upgrade:

   ```yaml
   metadata:
     annotations:
       traefik.ingress.kubernetes.io/router.middlewares: demo-redirect-https@kubernetescrd
   ```

5. **Enforce TLS** on all future Ingresses by default.

---


## Summary

> This step created a **private Certificate Authority** on your laptop and used it to sign a TLS certificate for `whoami.lab.local`. The CA private key stays local; only the **public** certificate and the **application** key/cert pair move into the Kubernetes cluster as a TLS Secret.

---

## References

- [OpenSSL `req` Manual](https://www.openssl.org/docs/man3.0/man1/openssl-req.html)
- [OpenSSL `x509` Manual](https://www.openssl.org/docs/man3.0/man1/openssl-x509.html)
- [RFC 5280 — X.509 PKI Certificate Profile](https://datatracker.ietf.org/doc/html/rfc5280)
- [Kubernetes TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)
- [Kubernetes Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)
- [Kubernetes TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)
- [Traefik TLS Configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/#tls)
- [OpenSSL Verify Manual](https://www.openssl.org/docs/man3.0/man1/openssl-verify.html)
- [curl `--resolve` Manual](https://curl.se/docs/manpage.html#--resolve)
