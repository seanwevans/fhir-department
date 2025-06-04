#!/usr/bin/env python

""" src/4.2-reuse.py"""


import requests


def cross_validate_with_external(resource: dict, validation_url: str) -> dict:
    """
    Hypothetical function that sends the resource to an external validation service.

    :param resource: FHIR resource dictionary
    :param validation_url: Endpoint that validates or enriches the resource
    :return: Original resource with 'validationResults' or updated data
    """
    try:
        # POST the resource to an external service that checks for known codes, etc.
        # For example, you might have a FHIR Terminology Server or a custom validation endpoint
        response = requests.post(validation_url, json=resource, timeout=5)
        if response.status_code == 200:
            validation_info = response.json()
            resource["validationResults"] = validation_info.get("results", [])
        else:
            resource["validationResults"] = [
                {
                    "error": f"Validation service responded with status {response.status_code}"
                }
            ]
    except requests.exceptions.RequestException as e:
        resource["validationResults"] = [{"error": str(e)}]

    return resource


def main():
    patient_resource = {
        "resourceType": "Patient",
        "id": "12345",
        "name": [{"family": "Doe", "given": ["John"]}],
    }

    validation_url = "https://example.com/validate"

    validated_resource = cross_validate_with_external(patient_resource, validation_url)
    print("Resource with external validation info:", validated_resource)


if __name__ == "__main__":
    main()
