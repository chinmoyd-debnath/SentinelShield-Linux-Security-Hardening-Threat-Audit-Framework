# SentinelShield: Linux Security Hardening and Threat Audit Framework

## Overview

SentinelShield is a Bash-based Linux security auditing and hardening framework built for academic and defensive cybersecurity practice. It provides a terminal-based interface for running Linux security checks, validating SSH security policies, scanning open ports, reviewing SUID/SGID binaries, checking enabled/running services, applying SSH hardening, rolling back SSH configuration backups, generating security reports, and demonstrating CPU scheduling concepts.

The tool uses "whiptail" to provide a menu-driven terminal UI.

## Key Features

- Basic Linux security scan
- World-writable file and directory checks
- Sticky-bit check for risky common directories
- SSH policy validation using an INI policy file
- Open/listening ports scan using `ss` or `netstat`
- SUID/SGID binary scan
- Enabled and running services review
- SSH hardening with automatic backup
- SSH configuration rollback from backup
- Security report generation with score and log
- Manual configuration backup
- CPU scheduling algorithms: FCFS, SJF, Round Robin
- CPU scheduling demo using `renice`

## Technologies Used

- Bash scripting
- Linux
- Whiptail terminal UI
- SSH configuration hardening
- System security auditing
- File permission auditing
- Service inspection
- Port scanning
- CPU scheduling simulation

## Requirements

Install required tools:

```bash
sudo apt update
sudo apt install -y whiptail iproute2 net-tools procps
```

## Documentation

- [Project Presentation](docs/sentinelshield-presentation.pdf)


  ## Screenshots

### Main Menu
![Main Menu](screenshots/01-main-menu.png)

### Basic Security Scan
![Basic Security Scan](screenshots/02-basic-security-scan.png)

### Policy Validation
![Policy Validation](screenshots/03-policy-validation.png)

### Open Ports Scan
![Open Ports Scan](screenshots/04-open-ports-scan.png)

### SUID/SGID Scan
![SUID/SGID Scan](screenshots/05-suid-sgid-scan.png)

### Services Overview
![Services Overview](screenshots/06-services-overview.png)

### SSH Hardening
![SSH Hardening](screenshots/07-ssh-hardening.png)

### Rollback from Backup
![Rollback from Backup](screenshots/08-rollback-backup.png)

### Security Report Generated
![Security Report Generated](screenshots/09-security-report-generated.png)

### CPU Scheduling Algorithms
![CPU Scheduling Algorithms](screenshots/10-cpu-scheduling-algorithms.png)

### Scheduling Sample Output
![Scheduling Sample Output](screenshots/11-scheduling-sample-output.png)

### CPU Scheduling Demo
![CPU Scheduling Demo](screenshots/12-cpu-scheduling-demo.png)

### Backup Created
![Backup Created](screenshots/13-backup-created.png)

