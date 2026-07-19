# SOP / Runbook — Lab 3: Splunk SIEM & Log Analysis

**Purpose:** Standard operating procedure to provision Splunk infrastructure on Azure via Terraform, install Splunk Enterprise, forward Windows Event Logs from the Lab 1 Active Directory VM, and stand up basic detection (dashboard + alert).

**Owner:** Home lab (Azure Free Account)
**Systems in scope:** Splunk Ubuntu VM (Terraform-provisioned), Windows Server VM (existing, from Lab 1)
**Provisioning method:** Terraform (IaC) — see [`terraform/`](terraform/)

---

## 1. Pre-requisites

- [ ] Lab 1 completed — Windows Server VM exists and is reachable; note its **VNet CIDR** (commonly `10.0.0.0/16`)
- [ ] Azure Free Account with quota available for a second VM
- [ ] Azure CLI installed, authenticated (`az login`)
- [ ] Terraform CLI installed (`terraform -version` ≥ 1.7.0)
- [ ] VS Code with the HashiCorp Terraform extension
- [ ] A local SSH key pair (`ssh-keygen -t ed25519` if you don't have one)
- [ ] A temporary email address for Splunk account registration (see §2)

---

## 2. Get Splunk Free

Splunk Enterprise is free to download: 60-day full trial → auto-converts to the free 500MB/day license. No credit card required.

**Do NOT use your real personal email/details for the Splunk registration form.** Use a disposable identity:

1. Go to `temp-mail.org/en/` — a temp email is generated automatically on page load
2. Go to `splunk.com/en_us/download/splunk-enterprise.html`, register using the temp-mail address; fill remaining fields with dummy info (fields are unverified)
3. Check the temp-mail inbox for the confirmation email, click the link
4. Download **Splunk Enterprise for Linux (.deb)** — not Splunk Cloud, not Splunk SOAR

> 🔒 **Security callout:** a free trial account tied to real identity info is an unnecessary exposure surface for a throwaway home-lab resource. In production you'd use a properly provisioned corporate account instead — the pattern to internalize is *scope your credentials to the sensitivity of what they protect*.

---

## 3. Provision the Splunk VM with Terraform

This replaces manual Azure Portal VM creation entirely. All infrastructure — resource group, VNet, subnet, NSG, static public IP, NIC, and the VM itself — is defined as code in [`terraform/`](terraform/).

```bash
cd lab3-splunk-siem/terraform

# 1. Copy the example vars file and fill in YOUR values
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
my_ip_cidr   = "YOUR_PUBLIC_IP/32"   # get yours at https://ifconfig.me
ad_vnet_cidr = "10.0.0.0/16"          # your Lab 1 AD VM's VNet CIDR
```

```bash
# 2. Initialize — downloads the azurerm provider plugin
terraform init

# 3. Preview exactly what will be created — nothing is changed yet
terraform plan

# 4. Apply — confirm with "yes" when prompted
terraform apply
```

**What gets created, and why each piece exists:**

| Resource | Purpose |
|---|---|
| Resource Group (`rg-lab3-splunk`) | Logical container — one command tears down the whole lab when you're done |
| VNet (`10.1.0.0/16`) + Subnet | Isolated network, deliberately non-overlapping with the Lab 1 AD VNet so they can be peered later without a CIDR conflict |
| NSG (3 rules) | SSH (22) and Web UI (8000) scoped to **your IP only**; forwarder input (9997) scoped to the **AD VNet CIDR only** — never the public internet |
| Static Public IP | Survives VM stop/start — no IP-reassignment surprises breaking your SSH session or NSG rules |
| NIC | Connects the VM to the subnet and public IP |
| Ubuntu 22.04 VM (`Standard_B2s`) | SSH-key-only authentication (`disable_password_authentication = true`) — matches Splunk's minimum 2 vCPU / 4GB RAM requirement, 30GB OS disk |

Full command reference and troubleshooting for the Terraform workflow itself: [`terraform/README.md`](terraform/README.md).

**Verify:** at the end of `apply`, Terraform prints outputs including the public IP and a ready-to-use SSH command:
```bash
terraform output
```

---

## 4. SSH In and Install Splunk

```bash
ssh -i ~/.ssh/id_ed25519 azureuser@$(terraform output -raw public_ip_address)
```

On the VM:

```bash
# 1. Download the installer (get the current wget command from Splunk's download page —
#    version numbers change; a 404 here just means a newer release exists)
wget -O splunk-10.2.2-linux-amd64.deb \
  "https://download.splunk.com/products/splunk/releases/10.2.2/linux/splunk-10.2.2-8b90d638de6-linux-amd64.deb"

# 2. Install (a Python 3.7 warning is expected/harmless — Splunk 10.x ships its own Python)
sudo dpkg -i splunk-10.2.2-linux-amd64.deb

# 3. Start Splunk, accept license, create admin credentials interactively
sudo /opt/splunk/bin/splunk start --accept-license --run-as-root

# 4. Register as a boot-start service so it survives VM reboots
sudo /opt/splunk/bin/splunk enable boot-start
```

**Verify:** browse to the URL from `terraform output splunk_web_ui_url` (or `http://<public_ip>:8000`) and confirm the login page loads.

> 💡 **Why this step is still manual (for now):** Terraform's job ends at "infrastructure exists and is reachable." Installing and configuring software on top of that infrastructure is configuration management's job — a natural next step here would be handing this off to **Ansible**, or baking the install into a **cloud-init** script referenced from `main.tf`. Worth doing as a follow-up exercise once you're comfortable with the manual steps.

---

## 5. Configure Splunk to Receive Data

In the Splunk web UI:

1. **Settings → Forwarding and Receiving → Configure Receiving → New Receiving Port → `9997` → Save**
2. **Settings → Indexes → Create New Index → name it `windows_logs` → Save**

---

## 6. Install & Configure the Universal Forwarder (Windows Server VM)

On the **Windows Server VM** (not the Splunk VM):

1. Download the Windows 64-bit Universal Forwarder from `splunk.com/en_us/download/universal-forwarder.html` (log in with the same account from §2)
2. Run the installer:
   - **Deployment Server** field → leave blank
   - **Receiving Indexer** → Splunk VM's **private IP** (`terraform output -raw private_ip_address`) + port 9997 (e.g. `10.1.1.4:9997`)
3. Deploy `inputs.conf` (provided in this repo at [`scripts/inputs.conf`](scripts/inputs.conf)) to:
   ```
   C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf
   ```
   (create the `local` folder if it doesn't exist)
4. Restart the forwarder to apply:
   ```powershell
   Restart-Service SplunkForwarder
   ```

> 💡 **Why `inputs.conf` matters:** this is the single file that decides what data actually leaves the Windows box. Get the `index=windows_logs` line wrong (or omit it) and your events land in Splunk's default `main` index instead — searches scoped to `index=windows_logs` will return nothing, and you'll spend twenty minutes debugging the wrong layer of the stack. Always check `inputs.conf` first when data "isn't showing up."

---

## 7. Generate Test Data

Fresh VMs have near-empty Security/System/Application logs. Run the provided generator to create realistic activity (failed logons, a successful logon, service restarts, app events, an account lockout):

```powershell
# Run as Administrator on the Windows Server VM
.\generate-test-logs.ps1
```

Script details in [`scripts/generate-test-logs.ps1`](scripts/generate-test-logs.ps1). It creates and then deletes a temporary local account (`labtest.user`) — no permanent changes to the VM.

**Wait 60 seconds** after the script finishes, then verify in Splunk (time range = All Time):

```spl
index=windows_logs | head 100
```

If this returns events, the forwarder → indexer pipeline is confirmed working.

---

## 8. Core SPL Searches

**Confirm data flow:**
```spl
index=windows_logs | head 100
```

**Successful logins by account:**
```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4624
| stats count by Account_Name
| sort -count
```

**After-hours logins (before 7am or after 7pm):**
```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4624
| eval hour=strftime(_time, "%H")
| where hour < 7 OR hour > 19
| table _time, Account_Name, Account_Domain, ComputerName
| sort -_time
```
> Note: account names ending in `$` are computer accounts — normal. A human account without `$` logging in after hours warrants review.

---

## 9. Build the Dashboard

**Dashboards → Create New Dashboard** → Title: `Windows Security Overview` → Classic Dashboards → Create.

| Panel | SPL | Visualization |
|---|---|---|
| Account Activity — Last 24h | `index=windows_logs sourcetype=WinEventLog:Security EventCode=4624 \| stats count by Account_Name \| sort -count` | Bar chart |
| Top Processes — Last 24h | `index=windows_logs sourcetype=WinEventLog:Security EventCode=4688 \| stats count by Creator_Process_Name \| sort -count \| head 20` | Events list |
| Login Activity Over Time | `index=windows_logs sourcetype=WinEventLog:Security EventCode=4624 \| timechart count` | Line chart |
| After-Hours Logins | (see §8 after-hours search) | Events list |

---

## 10. Build the Alert

Run first to confirm it works:
```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4672
| stats count as privilege_logons by Account_Name, ComputerName
| where privilege_logons > 50
```

**Save As → Alert:**
- Name: `High Privileged Logon Count`
- Type: Scheduled, Cron: `*/15 * * * *`
- Trigger: Number of Results > 0
- Action: Add to Triggered Alerts

> 💡 **Tuning note:** the 50-event threshold is a *starting point*, not a settled answer. In production you'd baseline normal privileged-logon volume for a week or two (segmented by account type — service accounts vs. human admins have very different "normal") before setting a real threshold. Too low → alert fatigue, real alerts get ignored. Too high → you miss genuine privilege abuse.

---

## 11. Verification Checklist

| Check | Expected result |
|---|---|
| `terraform output` | Shows public IP, private IP, SSH command, web UI URL |
| `index=windows_logs \| head 10` | Returns recent events |
| EventCode=4624 search | Returns results immediately |
| Windows Security Overview dashboard | All 4 panels populated |
| Settings → Searches, Reports, and Alerts | Alert shows as **Enabled** |

---

## 12. Troubleshooting

### Terraform apply fails
- **`Error: building account: unable to configure ResourceManagerAccount`** — run `az login` again; CLI session likely expired
- **`Error: A resource with the ID ... already exists`** — something with that name already exists outside Terraform's state (e.g. created manually in a prior attempt). Either rename the resource in `variables.tf` or `terraform import` the existing one — don't delete blind
- **Provider download fails / times out** — check your network can reach `registry.terraform.io`; corporate/restrictive networks sometimes block it

### Browser can't reach `http://VM-IP:8000`
1. **NSG rule wrong** — confirm `terraform.tfvars` has the CORRECT current `my_ip_cidr` (your IP may have changed since you last applied — home ISPs frequently rotate dynamic IPs). If it changed, update `terraform.tfvars` and re-run `terraform apply` to update the NSG rule.
2. **Splunk not running** — SSH in, run `sudo /opt/splunk/bin/splunk status`; expect `splunkd is running`. If stopped: `sudo /opt/splunk/bin/splunk start --accept-license --run-as-root`
3. **Splunk not listening** — `sudo ss -tlnp | grep 8000`; expect a line showing `0.0.0.0:8000` with `splunkd`
4. **Wrong IP** — always pull the current IP from `terraform output -raw public_ip_address`, not a value you wrote down previously. (Static allocation means it won't change on its own — but if you ever `terraform destroy`/`apply` again, you'll get a *new* static IP.)
5. **Forwarder can't reach port 9997** — confirm `ad_vnet_cidr` in `terraform.tfvars` matches your actual Lab 1 AD VNet's address space exactly (check Azure Portal → that VNet → Address space)
6. **VMs in different VNets, not peered** — NSG rules alone don't bridge VNets. Configure VNet Peering (Portal → Virtual Networks → your VNet → Peerings → Add), wait for status **Connected** on both links, then `Restart-Service SplunkForwarder` on the Windows VM.

> **Best practice for future labs:** for now this config deliberately uses a separate VNet to teach the peering pattern explicitly. Once you're comfortable with that, a future refactor could reference the Lab 1 VNet directly via a Terraform `data` source and deploy into a new subnet within it — avoiding peering entirely for labs that don't need network isolation from each other.

### Data isn't showing up in `windows_logs`
- Check `inputs.conf` on the Windows VM for a missing or wrong `index=windows_logs` line (see §6 callout)
- Confirm `Restart-Service SplunkForwarder` was run after any `inputs.conf` edit
- Confirm receiving is enabled on the Splunk side (§5, step 1)

---

## 13. Tearing Down / Rebuilding

```bash
cd terraform
terraform destroy   # stops the Azure meter when you're done for the day
# ...later...
terraform apply     # rebuilds an identical environment in ~3 minutes
```

> ⚠️ Splunk itself is installed manually (§4) and is **not** captured by Terraform — `destroy`/`apply` gives you back the *infrastructure*, not the installed application or its data. Re-running §4–§10 is currently required after a rebuild. This is exactly the gap that cloud-init or Ansible would close (see the callout in §4).

---

## 14. Appendix — Additional Queries (Richer Environments)

Included for reference; not required to complete this lab — useful once the environment has more activity history.

**Explicit credential logon (4648)** — common in lateral movement / credential abuse:
```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4648
| table _time, Account_Name, Target_Server_Name, Process_Name
| sort -_time
```

**Process creation (4688)** — foundation of endpoint detection:
```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4688
| stats count by Creator_Process_Name
| sort -count
| head 20
```

**Service installation (4697)** — favorite persistence mechanism for malware:
```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4697
| table _time, Account_Name, Service_Name, Service_File_Name
| sort -_time
```

---

## 15. Interview Talking Points

- Why you provisioned this with Terraform instead of the Azure Portal — reproducibility, code review, drift detection, fast teardown/rebuild
- Why the forwarder/indexer split mirrors real enterprise architecture
- Why NSG scoping matters for a data-ingest port specifically, and why it's defined in version-controlled code rather than a Portal click
- What a SIEM's two core jobs are (correlation + alerting) and why neither works without the other
- How you'd move from "the alert threshold I guessed" to "the alert threshold backed by baseline data"
- What the natural next step is for closing the gap between "infra is code" and "the whole stack is code" (cloud-init / Ansible for the Splunk install itself)
