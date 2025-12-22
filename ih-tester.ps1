Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Website Network Diagnostic Tool"
$form.Size = New-Object System.Drawing.Size(500,260)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter customer website domain name:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(20,20)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(440,20)
$textBox.Location = New-Object System.Drawing.Point(20,50)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(20,80)
$statusLabel.ForeColor = [System.Drawing.Color]::Blue

$button = New-Object System.Windows.Forms.Button
$button.Text = "Start Test"
$button.Size = New-Object System.Drawing.Size(120,30)
$button.Location = New-Object System.Drawing.Point(180,110)

$form.Controls.AddRange(@($label,$textBox,$statusLabel,$button))

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
        [System.Windows.Forms.MessageBox]::Show("Domain name is empty","Error")
        return
    }

    $statusLabel.Text = "Test started... please wait"
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
    try {
        $clientInfo = Invoke-RestMethod -Uri "https://www.nginxweb.ir/ip.php?country" -TimeoutSec 5
        Write-Log "Client Public IP Info:"
        Write-Log $clientInfo
    } catch {
        Write-Log "Client Public IP Info: Failed to retrieve"
    }

    Write-Log "=================================================="

    # Ping
    Write-Log "Ping Test (timeout 4 seconds):"
    cmd /c "ping -n 4 -w 1000 $domain" | ForEach-Object { Write-Log $_ }

    Write-Log "=================================================="

    # تست پورت‌ها
    Write-Log "Port Connectivity Tests:"
    Write-Log "TCP Port 80 (HTTP): $(Test-TcpPort -hostname $domain -port 80 -timeoutMs 5000)"
    Write-Log "TCP Port 443 (HTTPS): $(Test-TcpPort -hostname $domain -port 443 -timeoutMs 5000)"
    Write-Log "TCP Port 25 (SMTP): $(Test-TcpPort -hostname $domain -port 25 -timeoutMs 5000)"
    Write-Log "TCP Port 110 (POP3): $(Test-TcpPort -hostname $domain -port 110 -timeoutMs 5000)"

    Write-Log "=================================================="

    # Traceroute
    Write-Log "Traceroute (max 30 hops):"
    cmd /c "tracert -d $domain" | ForEach-Object { Write-Log $_ }

    Write-Log "=================================================="

    # HTTP
    Write-Log "HTTP Request Test (timeout 10 seconds):"
    try {
        $req = Invoke-WebRequest -Uri "http://$domain" -UseBasicParsing -TimeoutSec 10
        Write-Log "HTTP Status Code: $($req.StatusCode)"
        Write-Log "HTTP Status Description: $($req.StatusDescription)"
    } catch {
        Write-Log "HTTP Request Failed or Timed Out"
    }

    # HTTPS
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

    [System.Windows.Forms.MessageBox]::Show(
        "All tests completed successfully`nResult saved to:`n$filePath",
        "Test Finished"
    )

    $statusLabel.Text = ""
    Start-Sleep -Seconds 1
    $form.Close()
})

$form.ShowDialog()
