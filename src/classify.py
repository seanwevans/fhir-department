#!/usr/bin/env python

""" classify.py - step 1.1 of the fhir hose """


import json
import subprocess

import redis


def get_file_from_redis(
    queue_name="file_queue", redis_host="localhost", redis_port=6379
):
    """Fetches a file path from the Redis queue."""

    r_queue = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
    file_path = r_queue.lpop(queue_name)

    return file_path


def get_mime_type(file_path):
    """Runs `file --brief --mime` and parses the output."""

    try:
        result = subprocess.run(
            ["file", "--brief", "--mime", file_path],
            capture_output=True,
            text=True,
            check=True,
        )
        mime_output = result.stdout.strip()

        # Parse output like "type/format; charset=charset"
        mime_parts = mime_output.split("; ")
        type_format = mime_parts[0].split("/")
        charset = (
            mime_parts[1].split("=")[1]
            if len(mime_parts) > 1 and "charset=" in mime_parts[1]
            else None
        )

        mime_data = {
            "type": type_format[0] if len(type_format) > 0 else None,
            "format": type_format[1] if len(type_format) > 1 else None,
            "charset": charset,
        }
        return mime_data
    except subprocess.CalledProcessError as exc:
        return {"error": "Failed to determine MIME type", "details": str(exc)}


def main():
    """script entry-point"""

    file_path = get_file_from_redis()
    if not file_path:
        print(json.dumps({"error": "No file found in queue"}))
        return

    mime_info = get_mime_type(file_path)
    print(json.dumps(mime_info))


if __name__ == "__main__":
    main()
