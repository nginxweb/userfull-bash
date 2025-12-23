Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "ابزار عیب‌یابی شبکه وب‌سایت IRANHOST"
$form.Size = New-Object System.Drawing.Size(550, 320)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Tahoma", 10)

$label = New-Object System.Windows.Forms.Label
$label.Text = "آدرس وب سایت خود را جهت تست وارد کنید فقط نام دامنه وارد شود:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Font = New-Object System.Drawing.Font("Tahoma", 10, [System.Drawing.FontStyle]::Regular)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(500, 35)
$textBox.Location = New-Object System.Drawing.Point(20, 50)
$textBox.Font = New-Object System.Drawing.Font("Tahoma", 12, [System.Drawing.FontStyle]::Regular)
$textBox.Multiline = $true
$textBox.Height = 35
$textBox.Padding = New-Object System.Windows.Forms.Padding(8)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(20, 95)
$statusLabel.ForeColor = [System.Drawing.Color]::Blue
$statusLabel.Font = New-Object System.Drawing.Font("Tahoma", 9, [System.Drawing.FontStyle]::Regular)

$button = New-Object System.Windows.Forms.Button
$button.Text = "شروع تست"
$button.Size = New-Object System.Drawing.Size(140, 40)
$button.Location = New-Object System.Drawing.Point(200, 130)
$button.Font = New-Object System.Drawing.Font("Tahoma", 10, [System.Drawing.FontStyle]::Bold)

$form.Controls.AddRange(@($label, $textBox, $statusLabel, $button))

# تابع تست TCP پورت
function Test-TcpPort {
    param(
        [string]$hostname,
        [int]$port,
        [int]$timeoutMs
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $result = $client.BeginConnect($hostname, $port, $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne($timeoutMs, $false)

        if ($success -and $client.Connected) {
            $client.EndConnect($result)
            $client.Close()
            return "Connection Successful"
        } else {
            $client.Close()
            return "Connection Timed Out"
        }
    } catch {
        return "Connection Failed"
    }
}

# تابع بررسی آدرس DNS
function Get-DNSInfo {
    param(
        [string]$hostname
    )
    
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($hostname) | ForEach-Object { $_.IPAddressToString }
        return $ips -join ", "
    } catch {
        return "DNS resolution failed"
    }
}

# تابع تمیز کردن نام فایل
function Clean-FileName {
    param([string]$fileName)
    
    # حذف کاراکترهای غیرمجاز در نام فایل
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        $fileName = $fileName.Replace($char, '_')
    }
    
    # حذف کاراکترهای اضافی
    $fileName = $fileName.Replace(':', '_')
    $fileName = $fileName.Replace('/', '_')
    $fileName = $fileName.Replace('\', '_')
    $fileName = $fileName.Replace('?', '_')
    $fileName = $fileName.Replace('*', '_')
    $fileName = $fileName.Replace('<', '_')
    $fileName = $fileName.Replace('>', '_')
    $fileName = $fileName.Replace('|', '_')
    $fileName = $fileName.Replace('"', '_')
    
    # محدود کردن طول نام فایل
    if ($fileName.Length -gt 100) {
        $fileName = $fileName.Substring(0, 100)
    }
    
    return $fileName
}

$button.Add_Click({

    $domain = $textBox.Text.Trim()
    
    # فقط بررسی وجود دامنه
    if (!$domain) {
        [System.Windows.Forms.MessageBox]::Show("نام دامنه خالی است", "خطا", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $statusLabel.Text = "لطفا منتظر بمانید تا تست تکمیل شود..."
    $button.Enabled = $false
    $form.Refresh()

    $startTime = Get-Date
    
    # تمیز کردن نام دامنه برای استفاده در نام فایل
    $cleanDomain = Clean-FileName -fileName $domain
    $filePath = Join-Path (Get-Location) "network_test_$($cleanDomain)_$(Get-Date -Format yyyyMMdd_HHmmss).txt"

    function Write-Log {
        param($text)
        try {
            Add-Content -Path $filePath -Value $text -Encoding UTF8 -ErrorAction Stop
        } catch {
            # اگر خطا در نوشتن فایل رخ داد، در کنسول نمایش بده
            Write-Host "خطا در نوشتن فایل: $_"
        }
    }

    try {
        Write-Log "Network Diagnostic Report"
        Write-Log "Domain: $domain"
        Write-Log "Mail Domain: mail.$domain"
        Write-Log "Start Time: $startTime"
        Write-Log "=================================================="

        # IP و ISP مشتری
        $statusLabel.Text = "دریافت اطلاعات IP..."
        $form.Refresh()
        try {
            $clientInfo = Invoke-RestMethod -Uri "https://www.nginxweb.ir/ip.php?country" -TimeoutSec 5
            Write-Log "Client Public IP Info:"
            Write-Log $clientInfo
        } catch {
            Write-Log "Client Public IP Info: Failed to retrieve"
        }

        Write-Log "=================================================="

        # DNS Resolution برای دامنه اصلی
        $statusLabel.Text = "در حال بررسی DNS..."
        $form.Refresh()
        Write-Log "DNS Resolution:"
        Write-Log "Main Domain ($domain) IP Addresses: $(Get-DNSInfo -hostname $domain)"
        Write-Log "Mail Domain (mail.$domain) IP Addresses: $(Get-DNSInfo -hostname "mail.$domain")"

        Write-Log "=================================================="

        # Ping برای دامنه اصلی و mail
        $statusLabel.Text = "در حال انجام تست Ping..."
        $form.Refresh()
        Write-Log "Ping Test (timeout 4 seconds):"
        Write-Log "--- Main Domain ($domain) ---"
        $pingResult = cmd /c "ping -n 4 -w 1000 $domain" 2>&1
        $pingResult | ForEach-Object { Write-Log $_ }
        Write-Log ""
        Write-Log "--- Mail Domain (mail.$domain) ---"
        $pingResultMail = cmd /c "ping -n 4 -w 1000 mail.$domain" 2>&1
        $pingResultMail | ForEach-Object { Write-Log $_ }

        Write-Log "=================================================="

        # تست پورت‌ها برای دامنه اصلی
        $statusLabel.Text = "در حال آزمایش پورت‌ها..."
        $form.Refresh()
        Write-Log "Port Connectivity Tests for Main Domain ($domain):"
        Write-Log "TCP Port 80 (HTTP): $(Test-TcpPort -hostname $domain -port 80 -timeoutMs 5000)"
        Write-Log "TCP Port 443 (HTTPS): $(Test-TcpPort -hostname $domain -port 443 -timeoutMs 5000)"
        
        Write-Log ""
        Write-Log "=================================================="
        
        # تست پورت‌ها برای mail domain
        Write-Log "Port Connectivity Tests for Mail Domain (mail.$domain):"
        Write-Log "TCP Port 25 (SMTP): $(Test-TcpPort -hostname "mail.$domain" -port 25 -timeoutMs 5000)"
        Write-Log "TCP Port 110 (POP3): $(Test-TcpPort -hostname "mail.$domain" -port 110 -timeoutMs 5000)"
        Write-Log "TCP Port 143 (IMAP): $(Test-TcpPort -hostname "mail.$domain" -port 143 -timeoutMs 5000)"
        Write-Log "TCP Port 587 (SMTP Submission): $(Test-TcpPort -hostname "mail.$domain" -port 587 -timeoutMs 5000)"
        Write-Log "TCP Port 465 (SMTPS): $(Test-TcpPort -hostname "mail.$domain" -port 465 -timeoutMs 5000)"
        Write-Log "TCP Port 993 (IMAPS): $(Test-TcpPort -hostname "mail.$domain" -port 993 -timeoutMs 5000)"
        Write-Log "TCP Port 995 (POP3S): $(Test-TcpPort -hostname "mail.$domain" -port 995 -timeoutMs 5000)"

        Write-Log "=================================================="

        # Traceroute برای دامنه اصلی و mail
        $statusLabel.Text = "در حال اجرای Traceroute..."
        $form.Refresh()
        Write-Log "Traceroute (max 30 hops):"
        Write-Log "--- Main Domain ($domain) ---"
        $tracertResult = cmd /c "tracert -d $domain" 2>&1
        $tracertResult | ForEach-Object { Write-Log $_ }
        Write-Log ""
        Write-Log "--- Mail Domain (mail.$domain) ---"
        $tracertResultMail = cmd /c "tracert -d mail.$domain" 2>&1
        $tracertResultMail | ForEach-Object { Write-Log $_ }

        Write-Log "=================================================="

        # HTTP
        $statusLabel.Text = "در حال تست HTTP..."
        $form.Refresh()
        Write-Log "HTTP Request Test (timeout 10 seconds):"
        try {
            $req = Invoke-WebRequest -Uri "http://$domain" -UseBasicParsing -TimeoutSec 10
            Write-Log "HTTP Status Code: $($req.StatusCode)"
            Write-Log "HTTP Status Description: $($req.StatusDescription)"
        } catch {
            Write-Log "HTTP Request Failed or Timed Out"
        }

        # HTTPS
        $statusLabel.Text = "در حال تست HTTPS..."
        $form.Refresh()
        Write-Log "HTTPS Request Test (timeout 10 seconds):"
        try {
            $req = Invoke-WebRequest -Uri "https://$domain" -UseBasicParsing -TimeoutSec 10
            Write-Log "HTTPS Status Code: $($req.StatusCode)"
            Write-Log "HTTPS Status Description: $($req.StatusDescription)"
        } catch {
            Write-Log "HTTPS Request Failed or Timed Out"
        }

        Write-Log "=================================================="
        
        # تست MX Records
        $statusLabel.Text = "در حال بررسی MX Records..."
        $form.Refresh()
        Write-Log "Mail Exchange (MX) Records Test:"
        try {
            Write-Log "MX Records for $domain :"
            $mxRecords = nslookup -type=mx $domain 2>&1
            if ($mxRecords) {
                $mxRecords | ForEach-Object { Write-Log $_ }
            } else {
                Write-Log "No MX records found or failed to retrieve"
            }
        } catch {
            Write-Log "MX Records lookup failed"
        }

        Write-Log "=================================================="

        $endTime = Get-Date
        Write-Log "End Time: $endTime"
        Write-Log "Test Status: Completed"
        Write-Log ""
        Write-Log "Summary:"
        Write-Log "- Main Domain Tested: $domain"
        Write-Log "- Mail Domain Tested: mail.$domain"
        Write-Log "- Web Ports Tested: 80, 443"
        Write-Log "- Mail Ports Tested: 25, 110, 143, 587, 465, 993, 995"

        $statusLabel.Text = "تست تکمیل شد"
        $form.Refresh()
        
        [System.Windows.Forms.MessageBox]::Show(
            "تمامی تست‌ها با موفقیت انجام شدند`n`nفایل گزارش ایجاد شده در مسیر:`n$filePath`n`nتست‌های انجام شده:`n- دامنه اصلی: $domain`n- دامنه ایمیل: mail.$domain`n- پورت‌های وب و ایمیل`n`nلطفا فایل گزارش را برای تیم پشتیبانی بفرستید.",
            "تست به پایان رسید",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "خطایی در اجرای تست‌ها رخ داد:`n$_",
            "خطا در اجرای تست",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } finally {
        $statusLabel.Text = ""
        $button.Enabled = $true
        $textBox.Text = ""
        $textBox.Focus()
    }
})

$form.ShowDialog()
