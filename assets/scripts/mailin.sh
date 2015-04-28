#!/usr/bin/env bash

# Wire this script to receive incoming email for request responses.

INPUT=$(mktemp -t foi-mailin-mail-XXXXXXXX)
OUTPUT=$(mktemp -t foi-mailin-output-XXXXXXXX)

# Read the email message from stdin, and write it to the file $INPUT
cat >"$INPUT"

/usr/bin/env /opt/s3putter <"$INPUT" >"$OUTPUT" 2>&1

ERROR_CODE=$?
if [ ! "$ERROR_CODE" = "0" ]
then
  # report exceptions somehow?
  rm -f "$INPUT" "$OUTPUT"
  # tell Postfix error was temporary, so try again later (no point bouncing message to authority)
  exit 75
fi

cat "$OUTPUT"
rm -f "$INPUT" "$OUTPUT"
exit 0
