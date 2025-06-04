#!/usr/bin/env python

""" src/4.1-reduce.py"""

import copy


def deduplicate_fhir_resources(resources: list[dict]) -> list[dict]:
    """
    Given a list of FHIR resources (potentially containing duplicates),
    produce a new list of unique or merged resources.

    :param resources: List of FHIR resource dictionaries
    :return: Deduplicated list of FHIR resource dictionaries
    """
    # This is a naive approach: we identify duplicates by 'id' if it exists.
    # In real scenarios, you might use more robust logic:
    # - compare resource types and IDs
    # - compare certain fields (like patient name or date, etc.)
    # - handle versioning

    seen = {}
    for res in resources:
        resource_id = res.get("id", None)
        resource_type = res.get("resourceType", "Unknown")
        key = f"{resource_type}-{resource_id}"

        if key not in seen:
            seen[key] = copy.deepcopy(res)
        else:
            # If you need to merge data, do it here:
            # e.g. merging arrays or taking the latest "effectiveDateTime", etc.
            existing = seen[key]
            # Merge logic example (very simplistic):
            if "extension" in res:
                existing_extensions = existing.get("extension", [])
                new_extensions = res["extension"]
                # Combine, ignoring duplicates
                for ext in new_extensions:
                    if ext not in existing_extensions:
                        existing_extensions.append(ext)
                existing["extension"] = existing_extensions

    return list(seen.values())


def main():
    resources = [
        {
            "resourceType": "Patient",
            "id": "12345",
            "name": [{"family": "Doe", "given": ["John"]}],
        },
        {
            "resourceType": "Patient",
            "id": "12345",  # Duplicate
            "name": [{"family": "Doe", "given": ["John"]}],
            "extension": [
                {"url": "http://example.org/fhir", "valueString": "Additional"}
            ],
        },
        {"resourceType": "Observation", "id": "obs-001", "status": "final"},
        {
            "resourceType": "Observation",
            "id": "obs-001",  # Duplicate
            "status": "final",
            "extension": [{"url": "http://example.org/fhir", "valueString": "Extra"}],
        },
    ]

    deduped = deduplicate_fhir_resources(resources)
    print("Deduplicated resources:", deduped)


if __name__ == "__main__":
    main()
