#!/usr/bin/env python

"""src/3.3-relational-model.py"""


from sqlalchemy import create_engine, Column, String, Integer
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

Base = declarative_base()


class PatientEntity(Base):
    __tablename__ = "patients"
    id = Column(Integer, primary_key=True)
    patient_id = Column(String)
    family_name = Column(String)
    given_name = Column(String)
    birth_date = Column(String)


class RelationalMapper:
    def __init__(self, db_url="sqlite:///fhir_entities.db"):
        self.engine = create_engine(db_url)
        Base.metadata.create_all(self.engine)
        self.Session = sessionmaker(bind=self.engine)

    def store_patient(self, entity_data: dict) -> None:
        """
        Save entity data to the 'patients' table, or update if patient_id exists.
        """
        session = self.Session()
        existing_patient = (
            session.query(PatientEntity)
            .filter(PatientEntity.patient_id == entity_data["patient_id"])
            .first()
        )

        if existing_patient:
            # Update existing
            existing_patient.family_name = entity_data.get(
                "family_name", existing_patient.family_name
            )
            existing_patient.given_name = entity_data.get(
                "given_name", existing_patient.given_name
            )
            existing_patient.birth_date = entity_data.get(
                "birth_date", existing_patient.birth_date
            )
        else:
            # Insert new
            new_patient = PatientEntity(
                patient_id=entity_data["patient_id"],
                family_name=entity_data["family_name"],
                given_name=entity_data["given_name"],
                birth_date=entity_data["birth_date"],
            )
            session.add(new_patient)
        session.commit()
        session.close()

    def retrieve_patient(self, patient_id: str) -> dict:
        """
        Retrieve a patient's record by ID.
        """
        session = self.Session()
        patient = (
            session.query(PatientEntity)
            .filter(PatientEntity.patient_id == patient_id)
            .first()
        )
        session.close()

        if not patient:
            return {}

        return {
            "patient_id": patient.patient_id,
            "family_name": patient.family_name,
            "given_name": patient.given_name,
            "birth_date": patient.birth_date,
        }


def main():
    entity_data = {
        "patient_id": "12345",
        "family_name": "Doe",
        "given_name": "John",
        "birth_date": "1980-01-01",
    }

    relational_mapper = RelationalMapper()
    relational_mapper.store_patient(entity_data)
    stored_data = relational_mapper.retrieve_patient("12345")
    print("Retrieved from DB:", stored_data)


if __name__ == "__main__":
    main()
