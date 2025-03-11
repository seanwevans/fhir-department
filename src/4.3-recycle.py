#!/usr/bin/env python

""" """

import argparse
import copy
from datetime import datetime
import os
import sys
import uuid


def construct_final_fhir_bundle(
    deduplicated_resources: list[dict],
    cross_validated_resources: list[dict] = None,
    bundle_type: str = "collection",
) -> dict:
    """
    Constructs a final FHIR Bundle that includes all relevant resources.

    :param deduplicated_resources: Resources that have been through the reduce (dedup) step
    :param cross_validated_resources: Optionally, resources that have been externally validated
    :param bundle_type: The type of FHIR Bundle (e.g. 'collection', 'transaction', 'batch', etc.)
    :return: A final FHIR Bundle dictionary
    """

    # Combine deduplicated and cross-validated resources if needed
    all_resources = copy.deepcopy(deduplicated_resources)
    if cross_validated_resources:
        all_resources.extend(cross_validated_resources)

    # Create entries in the FHIR Bundle format
    entries = []
    for res in all_resources:
        entries.append({"fullUrl": f"urn:uuid:{str(uuid.uuid4())}", "resource": res})

    # Construct a minimal FHIR Bundle
    bundle = {
        "resourceType": "Bundle",
        "id": str(uuid.uuid4()),
        "type": bundle_type,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "entry": entries,
    }

    return bundle


# file: main.py

from fhir_construction.reduce_dedup import deduplicate_fhir_resources
from fhir_construction.reuse_validation import cross_validate_with_external
from fhir_construction.recycle_constructor import construct_final_fhir_bundle


def main():
    # 1) Suppose we have multiple partial FHIR resources from Step 3
    raw_resources = [
        {
            "resourceType": "Patient",
            "id": "12345",
            "name": [{"family": "Doe", "given": ["John"]}],
        },
        {
            "resourceType": "Observation",
            "id": "obs-001",
            "status": "final",
            "code": {"text": "Blood Pressure"},
        },
        {
            "resourceType": "Observation",
            "id": "obs-001",  # Duplicate
            "status": "final",
            "code": {"text": "Blood Pressure"},
            "extension": [{"url": "http://example.org/fhir", "valueString": "Extra"}],
        },
    ]

    # 2) Reduce: Deduplicate resources
    deduped = deduplicate_fhir_resources(raw_resources)

    # 3) Reuse: Cross-validate each resource with an external service
    validation_url = "https://example.com/validate"
    validated_resources = []
    for r in deduped:
        validated_resources.append(cross_validate_with_external(r, validation_url))

    # 4) Recycle: Construct a final FHIR Bundle
    final_bundle = construct_final_fhir_bundle(
        deduplicated_resources=deduped,
        cross_validated_resources=validated_resources,
        bundle_type="collection",
    )

    print("Final FHIR Bundle:", final_bundle)


if __name__ == "__main__":
    main()
