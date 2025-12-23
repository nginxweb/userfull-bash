Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "ابزار عیب‌یابی شبکه وب‌سایت"
$form.Size = New-Object System.Drawing.Size(500, 280)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Tahoma", 10)

$label = New-Object System.Windows.Forms.Label
$label.Text = "نام دامنه وب‌سایت مشتری را وارد کنید:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Font = New-Object System.Drawing.Font("Tahoma", 10, [System.Drawing.FontStyle]::Regular)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(440, 35)
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
$button.Location = New-Object System.Drawing.Point(180, 130)
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

$button.Add_Click({

    $domain = $textBox.Text.Trim()
    if (!$domain) {
        [System.Windows.Forms.MessageBox]::Show("نام دامنه خالی است", "خطا", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $statusLabel.Text = "لطفا منتظر بمانید تا تست تکمیل شود..."
    $button.Enabled = $false
    $form.Refresh()

    $startTime = Get-Date
    $filePath = Join-Path (Get-Location) "network_test_$($domain)_$(Get-Date -Format yyyyMMdd_HHmmss).txt"

    function Write-Log {
        param($text)
        Add-Content -Path $filePath -Value $text -Encoding UTF8
    }

    Write-Log "Network Diagnostic Report"
    Write-Log "Domain: $domain"
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

    # Ping
    $statusLabel.Text = "در حال انجام تست Ping..."
    $form.Refresh()
    Write-Log "Ping Test (timeout 4 seconds):"
    cmd /c "ping -n 4 -w 1000 $domain" | ForEach-Object { Write-Log $_ }

    Write-Log "=================================================="

    # تست پورت‌ها
    $statusLabel.Text = "در حال آزمایش پورت‌ها..."
    $form.Refresh()
    Write-Log "Port Connectivity Tests:"
    Write-Log "TCP Port 80 (HTTP): $(Test-TcpPort -hostname $domain -port 80 -timeoutMs 5000)"
    Write-Log "TCP Port 443 (HTTPS): $(Test-TcpPort -hostname $domain -port 443 -timeoutMs 5000)"
    Write-Log "TCP Port 25 (SMTP): $(Test-TcpPort -hostname $domain -port 25 -timeoutMs 5000)"
    Write-Log "TCP Port 110 (POP3): $(Test-TcpPort -hostname $domain -port 110 -timeoutMs 5000)"

    Write-Log "=================================================="

    # Traceroute
    $statusLabel.Text = "در حال اجرای Traceroute..."
    $form.Refresh()
    Write-Log "Traceroute (max 30 hops):"
    cmd /c "tracert -d $domain" | ForEach-Object { Write-Log $_ }

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

    $endTime = Get-Date
    Write-Log "End Time: $endTime"
    Write-Log "Test Status: Completed"

    $statusLabel.Text = "تست تکمیل شد"
    $form.Refresh()
    
    [System.Windows.Forms.MessageBox]::Show(
        "تمامی تست‌ها با موفقیت انجام شدند`nفایل گزارش ایجاد شده در مسیر:`n$filePath`n`nلطفا فایل گزارش را برای تیم پشتیبانی بفرستید.",
        "تست به پایان رسید",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    $statusLabel.Text = ""
    $button.Enabled = $true
    $textBox.Text = ""
    $textBox.Focus()
})

$form.ShowDialog()
