"""Export users as BSON; restore only into an empty database. Sessions are omitted."""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
from bson import encode, decode_all
from dotenv import load_dotenv
from pymongo import MongoClient


def backup_users(db, destination):
    # Exclusive creation prevents accidentally overwriting an earlier backup.
    count = 0
    with Path(destination).open("xb") as output:
        for user in db.users.find():
            # A backup must not restore a pending password-reset credential.
            user.pop("passwordResetHash", None)
            user.pop("passwordResetExpiresAt", None)
            output.write(encode(user))
            count += 1
    return count


def restore_users(db, source):
    if db.users.estimated_document_count() or db.sessions.estimated_document_count():
        raise ValueError("Restore requires an empty target database; existing accounts are never overwritten.")
    users = decode_all(Path(source).read_bytes())
    if len({user["email"] for user in users}) != len(users):
        raise ValueError("Backup contains duplicate emails")
    db.users.create_index("email", unique=True)
    if users:
        db.users.insert_many(users, ordered=True)
    return len(users)


def main():
    load_dotenv(Path(__file__).with_name(".env"))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("backup", "restore"))
    parser.add_argument("--file", type=Path)
    parser.add_argument("--database", default=os.environ.get("MONGODB_DATABASE", "pcosense"))
    args = parser.parse_args()
    uri = os.environ.get("MONGODB_URI")
    if not uri:
        parser.error("Set MONGODB_URI in backend/.env")
    path = args.file
    if path is None and args.action == "backup":
        folder = Path(__file__).resolve().parents[1] / "backups"
        folder.mkdir(exist_ok=True)
        path = folder / (datetime.now(timezone.utc).strftime("users-%Y%m%d-%H%M%S") + ".bson")
    if path is None:
        parser.error("Restore requires --file")
    with MongoClient(uri, tz_aware=True) as connection:
        db = connection[args.database]
        count = backup_users(db, path) if args.action == "backup" else restore_users(db, path)
    print(f"{args.action}: {count} accounts; file: {path}")


if __name__ == "__main__":
    main()
