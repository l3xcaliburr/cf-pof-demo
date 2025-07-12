#!/bin/bash

# =============================================================================
# Apache Web Server Installation Script
# =============================================================================

# Update system packages
yum update -y

# Install Apache web server
yum install -y httpd

# Start Apache service
systemctl start httpd

# Enable Apache to start on boot
systemctl enable httpd

# Create a simple index page with instance information
cat <<HTML > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>POC Web Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f4f4f4; }
        .container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
        .info { margin: 20px 0; }
        .success { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">🚀 POC Web Server</h1>
        <div class="info">
            <p class="success">✅ Apache HTTP Server is running successfully!</p>
            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
            <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>
            <p><strong>Private IP:</strong> <span id="private-ip">Loading...</span></p>
            <p><strong>Region:</strong> ${region}</p>
            <p><strong>Deployment:</strong> Terraform + Auto Scaling Group</p>
        </div>
        <p><em>This server is deployed in a private subnet and accessible only through the Application Load Balancer.</em></p>
    </div>

    <script>
        // Fetch instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data)
            .catch(() => document.getElementById('instance-id').textContent = 'Not available');

        fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone')
            .then(response => response.text())
            .then(data => document.getElementById('az').textContent = data)
            .catch(() => document.getElementById('az').textContent = 'Not available');

        fetch('http://169.254.169.254/latest/meta-data/local-ipv4')
            .then(response => response.text())
            .then(data => document.getElementById('private-ip').textContent = data)
            .catch(() => document.getElementById('private-ip').textContent = 'Not available');
    </script>
</body>
</html>
HTML

# Set proper permissions
chown apache:apache /var/www/html/index.html
chmod 644 /var/www/html/index.html

# Log completion
echo "$(date): Apache installation and configuration completed" >> /var/log/user-data.log