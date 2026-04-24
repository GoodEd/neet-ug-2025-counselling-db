from etl.neetcounselling2025 import normalized_loader as mod


def test_normalize_program_maps_known_labels():
    assert mod.normalize_program("MBBS") == "MBBS"
    assert mod.normalize_program("BDS") == "BDS"
    assert mod.normalize_program("B.Sc Nursing") == "BSCN"


def test_normalize_result_category_maps_known_labels():
    assert mod.normalize_result_category("Open") == ("OPEN", False)
    assert mod.normalize_result_category("EWS") == ("EWS", False)
    assert mod.normalize_result_category("BC PwD") == ("OBC", True)


def test_extract_institution_details_reads_state_and_code():
    raw = "AIIMS, Patna,Phulwarisharif, Patna, Bihar-801507, Bihar, 801507 (200101)"

    details = mod.extract_institution_details(raw)

    assert details.mcc_institute_code == 200101
    assert details.state_name == "Bihar"
    assert details.display_name == "AIIMS, Patna"


def test_round_key_for_known_pdf_names():
    assert mod.round_key_for_pdf_name("Final Allotment Result for Stray Vacacy Round UG 2025 - 2025111596488171.pdf") == "STRAY"
    assert mod.round_key_for_pdf_name("Final Result for Special Stray Round of UG counselling 2025 - 202512231822103663.pdf") == "SPECIAL_STRAY"
    assert mod.round_key_for_pdf_name("Final Result of UG Counselling Round 5 for BDS ⁄ B.Sc Nursing 2025 - 202601031185987538.pdf") == "R5_BDS_BSCN"
