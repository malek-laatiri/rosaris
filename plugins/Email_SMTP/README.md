# Email SMTP plugin

![screenshot](https://gitlab.com/francoisjacquet/Email_SMTP/raw/master/screenshot.png?inline=false)

https://www.rosariosis.org/plugins/email-smtp/

Version 10.8 - April, 2026

[Change log](https://gitlab.com/francoisjacquet/Email_SMTP/-/commits/master?ref_type=HEADS)

Author François Jacquet

License GNU/GPLv2 or later

## Description

Send emails using SMTP instead of the default PHP `mail()` function.
Having problems with RosarioSIS not sending emails? Use this SMTP plugin to fix your email deliverability issues.

SMTP (Simple Mail Transfer Protocol) is a protocol for sending emails. SMTP helps increase email deliverability by using proper authentication. Just enter your email provider's SMTP server settings to relay emails sent by RosarioSIS.

Get help and settings for Gmail, Outlook and Yahoo in the [DOCUMENTATION.md](https://gitlab.com/francoisjacquet/Email_SMTP/blob/master/DOCUMENTATION.md) file.

Translated in [French](https://www.rosariosis.org/fr/plugins/email-smtp/), [Spanish](https://www.rosariosis.org/es/plugins/email-smtp/), Slovenian, Russian and Ukrainian.

## Content

Plugin Configuration

- From Email and Name.
- SMTP host and port.
- SSL or TLS encryption.
- SMTP username and password.
- Pause between each email (seconds).
- Send test email.

## Install

Copy the `Email_SMTP/` folder (if named `Email_SMTP-master`, rename it) and its content inside the `plugins/` folder of RosarioSIS.

Go to _School > Configuration > Plugins_ and click "Activate".

Requires RosarioSIS 3.6.1+ and PHP openssl extension
