# Mail Cleanup Scripts

Three template scripts for managing Apple Mail via SQLite database queries and AppleScript automation.

## How They Work

All scripts follow the same pattern:
1. Check that Mail.app sync is complete (exits if pending actions remain)
2. Count and display total messages matching criteria
3. Query the Mail SQLite database (`~/Library/Mail/V10/MailData/Envelope Index`)
4. Process messages in batches of 50
5. Use AppleScript to move/delete messages in Mail.app
6. Display progress after each batch (e.g., "Moved 47 messages (Total: 147 / 1523)")
7. Track failed operations separately
8. Sleep 2 seconds between batches to avoid overwhelming Mail
9. Loop until no more messages match the criteria

## The Three Templates

All templates are located in the `templates/` folder.

### 1. Deduplicate (`templates/template-deduplicate.sh`)

**Purpose:** Remove duplicate messages within a specific mailbox based on `global_message_id` (email Message-ID header).

**How it works:**
- Finds messages with duplicate `global_message_id` in the target mailbox
- Keeps the message with the lowest ROWID (oldest)
- Deletes all other copies to trash

**To customize:**
Edit the variables at the top of the script:
```bash
MAILBOX_FILTER="%INBOX%"           # SQL LIKE pattern
SOURCE_MAILBOX="INBOX"             # AppleScript mailbox name
TRASH_MAILBOX="Deleted Messages"   # AppleScript trash name
ACCOUNT_NUMBER=1                   # Mail.app account number (usually 1)
DRY_RUN=0                         # Set to 1 to preview without deleting
```

**Features:**
- Shows initial count of duplicates before starting
- Displays progress as "Deleted X messages (Total: Y / Z)"
- Tracks failed operations separately
- DRY_RUN mode to preview what would be deleted

**Example use cases:**
- Remove duplicates from Sent folder
- Remove duplicates from INBOX
- Remove duplicates from any custom folder

### 2. Delete by Criteria (`templates/template-delete.sh`)

**Purpose:** Delete messages matching specific sender/subject criteria.

**How it works:**
- Queries messages by sender address and/or subject text
- Moves matching messages to trash

**To customize:**
Edit the variables at the top of the script:
```bash
MAILBOX_FILTER="%INBOX%"                        # Source mailbox
SENDER_FILTER="a.address LIKE '%example.com'"   # Sender filter
SUBJECT_FILTER="s.subject LIKE '%Newsletter%'"  # Subject filter
USE_SUBJECT_FILTER=0                             # 1 to enable, 0 to disable
SOURCE_MAILBOX="INBOX"                          # AppleScript source name
TRASH_MAILBOX="Deleted Messages"                # AppleScript trash name
ACCOUNT_NUMBER=1                                # Mail.app account number (usually 1)
DRY_RUN=0                                       # Set to 1 to preview without deleting
```

**Features:**
- Shows initial count of matching messages before starting
- Displays progress as "Deleted X messages (Total: Y / Z)"
- Tracks failed operations separately
- DRY_RUN mode to preview what would be deleted

**Example use cases:**
- Delete automated notifications (trades, orders, receipts)
- Delete newsletters from specific senders
- Clean up promotional emails

### 3. Move by Criteria (`templates/template-move.sh`)

**Purpose:** Move messages matching specific criteria to a designated folder.

**How it works:**
- Queries messages by sender address (or other criteria)
- Moves matching messages to target folder

**To customize:**
Edit the variables at the top of the script:
```bash
SOURCE_MAILBOX_FILTER="%INBOX%"                  # Source mailbox SQL filter
SENDER_FILTER="a.address = 'example@domain.com'" # Sender filter
SOURCE_MAILBOX="INBOX"                           # AppleScript source name
DESTINATION_MAILBOX="DestinationFolder"          # AppleScript destination name
ACCOUNT_NUMBER=1                                 # Mail.app account number (usually 1)
DRY_RUN=0                                        # Set to 1 to preview without moving
```

**Features:**
- Shows initial count of matching messages before starting
- Displays progress as "Moved X messages (Total: Y / Z)"
- Tracks failed operations separately
- DRY_RUN mode to preview what would be moved

**Example use cases:**
- File emails by sender into folders
- Move emails from one folder to another
- Organize emails by domain/address

## Key Database Tables

- **messages**: Core message table with ROWID, global_message_id, date_received
- **mailboxes**: Mailbox URLs (e.g., `imap://...//INBOX`)
- **addresses**: Email addresses (sender, recipients)
- **subjects**: Email subjects
- **recipients**: Junction table linking messages to recipient addresses

## Important Notes

1. **Message IDs**: The `global_message_id` field represents the email's Message-ID header. Emails sent to yourself will have the same `global_message_id` in both Sent and received folders (this is expected, not a duplicate).

2. **IMAP Sync**: After running scripts, Mail.app syncs changes to the IMAP server. Check `local_message_actions` table to monitor pending sync operations:
   ```sql
   SELECT COUNT(*) FROM local_message_actions
   ```

3. **Account Setup**: Scripts default to `account 1` in AppleScript. Change the `ACCOUNT_NUMBER` variable if you have multiple accounts.

4. **Mailbox Names**: Default mailboxes are "INBOX", "Sent Messages", "Deleted Messages". Adjust for your server.

5. **Safety**: Scripts use LIMIT 50 and sleep 2 seconds to avoid rate limiting and database corruption. All scripts support `DRY_RUN=1` mode to preview changes without making them.

## Running a Script

### Before Running

All scripts automatically check that Mail.app has finished syncing before proceeding. If syncing is in progress, the script will exit with a message showing how many pending actions remain.

You can manually check sync status anytime:
```bash
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index "SELECT COUNT(*) FROM local_message_actions"
```

If the count is greater than 0, wait for it to reach 0 before running cleanup scripts.

### Running in Background

Scripts can take a long time to process thousands of messages. Run them in the background with caffeinate to prevent your Mac from sleeping:

```bash
chmod +x script-name.sh
caffeinate -i ./script-name.sh &
```

The script will output progress to the terminal and exit when complete.

### Checking Progress

While a script is running, you can check progress by:

1. **View script output:** The script prints status messages as it works
2. **Query the database:** Count remaining messages that match your criteria
3. **Check Mail.app Activity window:** Window > Activity shows IMAP sync progress

Example progress check:
```bash
# Check how many messages remain (adjust WHERE clause to match your script)
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "SELECT COUNT(*) FROM messages m
   JOIN mailboxes mb ON m.mailbox = mb.ROWID
   WHERE mb.url LIKE '%INBOX%'"
```

## Creating New Scripts

1. Copy one of the three templates from the `templates/` folder to the root directory:
   ```bash
   cp templates/template-delete.sh my-cleanup-script.sh
   ```

2. Edit the variables at the top of your new script:
   - Change mailbox filters
   - Change sender/subject criteria
   - Change mailbox names

3. Make it executable and run:
   ```bash
   chmod +x my-cleanup-script.sh
   ./my-cleanup-script.sh
   ```

4. When finished, delete the script to keep the directory clean:
   ```bash
   rm my-cleanup-script.sh
   ```

**Note:** Keep the templates in the `templates/` folder unchanged. Always copy from the templates when creating new scripts.

For advanced customization, you can modify the SQL queries and AppleScript directly.
