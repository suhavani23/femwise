"""Email transport for single-use, short-lived account recovery tokens."""
from email.message import EmailMessage
import os
import smtplib
import ssl


def recovery_configured():
    return bool(os.environ.get("SMTP_HOST") and os.environ.get("SMTP_FROM"))


def send_recovery_email(recipient, token):
    message = EmailMessage()
    message["From"] = os.environ["SMTP_FROM"]
    message["To"] = recipient
    message["Subject"] = "Reset your PCOSense password"
    message.set_content(
        "Paste this recovery code into PCOSense to choose a new password:\n\n"
        f"{token}\n\nThis code expires in 20 minutes and can be used once.\n"
        "If you did not request this, you can ignore this email.\n")
    mode = os.environ.get("SMTP_SECURITY", "starttls")
    if mode not in ("starttls", "ssl"):
        raise ValueError("SMTP_SECURITY must be starttls or ssl")
    port = int(os.environ.get("SMTP_PORT", "465" if mode == "ssl" else "587"))
    transport = smtplib.SMTP_SSL if mode == "ssl" else smtplib.SMTP
    options = {"context": ssl.create_default_context()} if mode == "ssl" else {}
    with transport(os.environ["SMTP_HOST"], port, timeout=15, **options) as server:
        if mode == "starttls":
            server.starttls(context=ssl.create_default_context())
        if os.environ.get("SMTP_USERNAME"):
            server.login(os.environ["SMTP_USERNAME"], os.environ.get("SMTP_PASSWORD", ""))
        server.send_message(message)
