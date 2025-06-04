#!/usr/bin/env python

""" src/3.1-templates.py """


import json
import jinja2


class TemplateMapper:
    def __init__(self, templates_path: str = "templates"):
        loader = jinja2.FileSystemLoader(searchpath=templates_path)
        self.env = jinja2.Environment(loader=loader)

    def map_entities_to_fhir(self, entity_data: dict, template_name: str) -> dict:
        """
        Renders a FHIR JSON structure from the provided entity_data using a Jinja2 template.

        :param entity_data: A dictionary of data extracted from previous steps
                            (e.g. { "patient_id": "1234", "family_name": "Doe", ... })
        :param template_name: Name of the template file (e.g. "fhir_patient_template.j2")
        :return: Dictionary representing a FHIR resource
        """
        template = self.env.get_template(template_name)
        rendered_str = template.render(entity_data)

        # Convert rendered JSON string into a Python dictionary
        fhir_resource = json.loads(rendered_str)
        return fhir_resource


def main():
    entity_data = {
        "patient_id": "12345",
        "family_name": "Doe",
        "given_name": "John",
        "birth_date": "1980-01-01",
        "additional_fields": [
            {
                "url": "http://example.org/fhir/StructureDefinition/patient-birthplace",
                "valueString": "New York",
            }
        ],
    }

    mapper = TemplateMapper(templates_path="templates")
    fhir_patient = mapper.map_entities_to_fhir(entity_data, "fhir_patient_template.j2")
    print(fhir_patient)


if __name__ == "__main__":
    main()
