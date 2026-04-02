<?php
/**
 * WordPress Scanner for cPanel Server
 * Run via SSH: php find_wordpress.php
 * Requires root or reseller access
 */

$results = [];
$errors  = [];

// ── Server Info ─────────────────────────────────────────────────────────────
$hostname  = php_uname('n');
$server_ip = gethostbyname($hostname);
$datetime  = date('Y-m-d H:i:s');

// ── 1. Get all cPanel accounts ──────────────────────────────────────────────
$cpanel_users = [];

// Method A: /etc/trueuserdomains
if (file_exists('/etc/trueuserdomains')) {
    $lines = file('/etc/trueuserdomains', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        [$domain, $user] = array_map('trim', explode(':', $line, 2));
        $cpanel_users[$user][] = $domain;
    }
}

// Method B: fallback
if (empty($cpanel_users) && is_dir('/var/cpanel/users')) {
    foreach (glob('/var/cpanel/users/*') as $file) {
        $user = basename($file);
        $cpanel_users[$user] = [];
    }
}

if (empty($cpanel_users)) {
    die("❌ Could not read cPanel user list. Run as root.\n");
}

echo "✅ Found " . count($cpanel_users) . " cPanel accounts.\n\n";

// ── 2. Find document roots ──────────────────────────────────────────────────
foreach ($cpanel_users as $user => $domains) {

    $home = "/home/{$user}";
    if (!is_dir($home)) $home = "/home2/{$user}";
    if (!is_dir($home)) { $errors[] = "Home dir not found for: $user"; continue; }

    $roots = [];

    // main domain
    if (is_dir("{$home}/public_html")) {
        $primary_domain = $domains[0] ?? $user;
        $roots[$primary_domain] = "{$home}/public_html";
    }

    // addon/sub domains
    $userdata_dir = "/var/cpanel/userdata/{$user}";
    if (is_dir($userdata_dir)) {
        foreach (glob("{$userdata_dir}/*") as $vhost_file) {
            $vhost_name = basename($vhost_file);
            if (str_ends_with($vhost_name, '_SSL') || $vhost_name === 'main') continue;

            $content = @file_get_contents($vhost_file);
            if (preg_match('/documentroot\s*:\s*(.+)/i', $content, $m)) {
                $docroot = trim($m[1]);
                if (is_dir($docroot)) {
                    $roots[$vhost_name] = $docroot;
                }
            }
        }
    }

    // ── 3. Detect WordPress ────────────────────────────────────────────────
    foreach ($roots as $domain => $docroot) {
        if (is_wordpress($docroot)) {
            $wp_version = get_wp_version($docroot);
            $results[] = [
                'user'       => $user,
                'domain'     => $domain,
                'path'       => $docroot,
                'wp_version' => $wp_version,
            ];
        }
    }
}

// ── 4. Output ───────────────────────────────────────────────────────────────
echo "Server: {$hostname}\n";
echo "Server IP: {$server_ip}\n";
echo "Scan Time: {$datetime}\n";
echo str_repeat('─', 100) . "\n";

printf("%-20s %-35s %-10s %s\n", 'USER', 'DOMAIN', 'WP VER', 'PATH');
echo str_repeat('─', 100) . "\n";

if (empty($results)) {
    echo "No WordPress installations found.\n";
} else {
    foreach ($results as $r) {
        printf("%-20s %-35s %-10s %s\n",
            $r['user'], $r['domain'], $r['wp_version'], $r['path']
        );
    }
}

echo str_repeat('─', 100) . "\n";
echo "Total WordPress installs: " . count($results) . "\n";

if (!empty($errors)) {
    echo "\n⚠️  Warnings:\n";
    foreach ($errors as $e) echo "  - $e\n";
}

// ── Helper functions ────────────────────────────────────────────────────────

function is_wordpress(string $dir): bool {
    return (
        file_exists("{$dir}/wp-config.php") ||
        file_exists("{$dir}/wp-login.php")  ||
        (is_dir("{$dir}/wp-includes") && is_dir("{$dir}/wp-admin"))
    );
}

function get_wp_version(string $dir): string {
    $ver_file = "{$dir}/wp-includes/version.php";
    if (file_exists($ver_file)) {
        $contents = file_get_contents($ver_file);
        if (preg_match('/\$wp_version\s*=\s*[\'"]([^\'"]+)[\'"]/', $contents, $m)) {
            return $m[1];
        }
    }
    return 'unknown';
}
