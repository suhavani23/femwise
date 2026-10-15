import mongomock
import pytest
from backup_accounts import backup_users, restore_users


def test_backup_round_trip_and_non_destructive_restore(tmp_path):
    connection = mongomock.MongoClient()
    source, target = connection.source, connection.target
    source.users.insert_one({"_id": "a", "email": "a@example.com", "passwordHash": "hashed",
        "profile": {"hasPCOS": True}, "dailyLogs": {"2026-10-15": {"notes": "hello"}},
        "passwordResetHash": "must-not-restore"})
    source.sessions.insert_one({"_id": "old-session"})
    path = tmp_path / "backup.bson"
    assert backup_users(source, path) == 1
    assert restore_users(target, path) == 1
    user = target.users.find_one()
    assert user["dailyLogs"]["2026-10-15"]["notes"] == "hello"
    assert "passwordResetHash" not in user
    assert target.sessions.count_documents({}) == 0
    with pytest.raises(ValueError, match="empty"):
        restore_users(target, path)
    with pytest.raises(FileExistsError):
        backup_users(source, path)
