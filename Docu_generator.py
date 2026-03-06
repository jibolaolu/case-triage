#!/usr/bin/env python3
"""
Case Triage Test Data Generator
Standalone Python Script for Local Testing

This script generates realistic UK applicant profiles and PDF documents,
then submits them to the Case Triage intake API for testing.

Usage:
    python3 simple_test_generator.py

Configuration:
    Edit INTAKE_API_URL below to match your API Gateway endpoint
"""

import json
import requests
import random
from datetime import datetime, timedelta
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch
import io
import sys

# ═══════════════════════════════════════════════════════════════════════
# CONFIGURATION - EDIT THIS SECTION
# ═══════════════════════════════════════════════════════════════════════

# Your API Gateway URL - REQUIRED
# Example: "https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod"
INTAKE_API_URL = "https://at20yw8lx5.execute-api.eu-west-2.amazonaws.com/dev"

# Optional: Add authorization token if your API requires it
# Example: "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
API_AUTHORIZATION_TOKEN = None  # Set to None if not needed

# Test mode: Set to True to skip actual API calls (for local PDF testing)
DRY_RUN_MODE = False

# Save PDFs locally for inspection
SAVE_PDFS_LOCALLY = False
LOCAL_PDF_PATH = "/tmp"  # Where to save PDFs if SAVE_PDFS_LOCALLY = True

# ═══════════════════════════════════════════════════════════════════════
# DATA SOURCES - UK Realistic Names and Locations
# ═══════════════════════════════════════════════════════════════════════

FIRST_NAMES = [
    "Emma", "Oliver", "Amelia", "Noah", "Isla", "Muhammad", "Aisha", "James",
    "Sophie", "Jack", "Lily", "Harry", "Grace", "George", "Freya", "Thomas",
    "Ava", "Oscar", "Mia", "William", "Olivia", "Yusuf", "Fatima", "Ali",
    "Zara", "Hassan", "Leah", "Adam", "Hannah", "Ibrahim", "Chloe", "Ryan"
]

LAST_NAMES = [
    "Smith", "Jones", "Williams", "Brown", "Taylor", "Davies", "Wilson",
    "Evans", "Thomas", "Johnson", "Roberts", "Khan", "Ahmed", "Ali", "Patel",
    "Singh", "O'Brien", "Murphy", "Kelly", "Ryan", "McCarthy", "Walsh",
    "Graham", "Lewis", "Walker", "Robinson", "Thompson", "White", "Hughes", "Clarke"
]

UK_CITIES = [
    "London", "Birmingham", "Manchester", "Liverpool", "Leeds", "Bristol",
    "Sheffield", "Edinburgh", "Glasgow", "Cardiff", "Newcastle", "Leicester",
    "Nottingham", "Southampton", "Brighton", "Plymouth", "Reading", "Oxford"
]

POSTCODES = {
    "London": ["E1", "W1", "SW1", "SE1", "N1", "NW1", "EC1", "E2", "W2"],
    "Birmingham": ["B1", "B2", "B3", "B4", "B5"],
    "Manchester": ["M1", "M2", "M3", "M4", "M5"],
    "Liverpool": ["L1", "L2", "L3", "L4"],
    "Leeds": ["LS1", "LS2", "LS3"],
    "Bristol": ["BS1", "BS2", "BS3"],
    "default": ["XX1", "YY2", "ZZ3"]
}


# ═══════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

def generate_ni_number():
    """Generate realistic UK National Insurance number"""
    letters = 'ABCEGHJKLMNOPRSTWXYZ'
    prefix = random.choice(letters) + random.choice(letters)
    digits = ''.join([str(random.randint(0, 9)) for _ in range(6)])
    suffix = random.choice('ABCD')
    return f"{prefix}{digits}{suffix}"


def generate_uk_postcode(city):
    """Generate realistic UK postcode"""
    code_list = POSTCODES.get(city, POSTCODES["default"])
    code = random.choice(code_list)
    return f"{code} {random.randint(1, 9)}{random.choice('ABCDEFGHJKLMNPQRSTUVWXY')}{random.choice('ABCDEFGHJKLMNPQRSTUVWXY')}"


def generate_applicant_profile(case_type, org_id):
    """Generate realistic applicant profile with financial data calibrated to case type"""

    first_name = random.choice(FIRST_NAMES)
    last_name = random.choice(LAST_NAMES)
    city = random.choice(UK_CITIES)

    # Age 18-65
    age = random.randint(18, 65)
    dob = (datetime.now() - timedelta(days=age * 365 + random.randint(0, 364))).strftime("%Y-%m-%d")

    # Financial data based on case type
    if case_type == "hardship-fund":
        monthly_income = random.randint(800, 2000)
        account_balance = random.randint(0, 1000)
        monthly_rent = int(monthly_income * random.uniform(0.35, 0.55))
    elif case_type == "housing-support":
        monthly_income = random.randint(1000, 2200)
        account_balance = random.randint(0, 1500)
        monthly_rent = int(monthly_income * random.uniform(0.32, 0.50))
    else:  # emergency-grant
        monthly_income = random.randint(600, 1200)
        account_balance = random.randint(0, 500)
        monthly_rent = int(monthly_income * random.uniform(0.40, 0.60))

    return {
        "firstName": first_name,
        "lastName": last_name,
        "dob": dob,
        "nationalInsurance": generate_ni_number(),
        "email": f"{first_name.lower()}.{last_name.lower()}@example.com",
        "phone": f"+44 7{random.randint(100, 999)} {random.randint(100, 999)}{random.randint(100, 999)}",
        "address": {
            "line1": f"{random.randint(1, 999)} {random.choice(['High', 'Main', 'Park', 'Church', 'Station', 'Queen', 'King'])} Street",
            "city": city,
            "postcode": generate_uk_postcode(city)
        },
        "monthlyIncome": monthly_income,
        "accountBalance": account_balance,
        "monthlyRent": monthly_rent,
        "employmentStatus": random.choice(["employed", "unemployed", "self-employed"])
    }


# ═══════════════════════════════════════════════════════════════════════
# PDF GENERATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

def create_bank_statement(applicant, month, year):
    """Generate bank statement PDF with realistic transactions"""
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4

    # Header
    c.setFont("Helvetica-Bold", 16)
    c.drawString(1 * inch, height - 1 * inch, "UK BANKING GROUP")
    c.setFont("Helvetica", 10)
    c.drawString(1 * inch, height - 1.3 * inch, "123 Banking Street, London, EC1A 1BB")

    # Account holder details
    c.setFont("Helvetica-Bold", 12)
    c.drawString(1 * inch, height - 2 * inch, "Account Statement")
    c.setFont("Helvetica", 10)
    c.drawString(1 * inch, height - 2.3 * inch, f"Account Holder: {applicant['firstName']} {applicant['lastName']}")
    c.drawString(1 * inch, height - 2.5 * inch, f"Account Number: {random.randint(10000000, 99999999)}")
    c.drawString(1 * inch, height - 2.7 * inch,
                 f"Sort Code: {random.randint(10, 99)}-{random.randint(10, 99)}-{random.randint(10, 99)}")
    c.drawString(1 * inch, height - 2.9 * inch, f"Statement Period: {month} {year}")

    # Address
    c.drawString(1 * inch, height - 3.3 * inch, applicant['address']['line1'])
    c.drawString(1 * inch, height - 3.5 * inch, f"{applicant['address']['city']}, {applicant['address']['postcode']}")

    # Transactions table header
    y_position = height - 5 * inch
    c.setFont("Helvetica-Bold", 9)
    c.drawString(1 * inch, y_position, "Date")
    c.drawString(2 * inch, y_position, "Description")
    c.drawString(4.5 * inch, y_position, "Debit")
    c.drawString(5.5 * inch, y_position, "Credit")
    c.drawString(6.5 * inch, y_position, "Balance")

    c.line(1 * inch, y_position - 5, 7 * inch, y_position - 5)

    # Generate transactions
    balance = applicant['accountBalance'] + random.randint(300, 600)
    c.setFont("Helvetica", 8)
    y_position -= 20

    # Opening balance
    c.drawString(1 * inch, y_position, f"01/{month[:3]}/{year}")
    c.drawString(2 * inch, y_position, "Opening Balance")
    c.drawRightString(7 * inch, y_position, f"£{balance:.2f}")
    y_position -= 15

    # Salary payment
    credit = applicant['monthlyIncome']
    balance += credit
    c.drawString(1 * inch, y_position, f"05/{month[:3]}/{year}")
    c.drawString(2 * inch, y_position,
                 "SALARY PAYMENT" if applicant['employmentStatus'] == 'employed' else "BENEFIT PAYMENT")
    c.drawRightString(5.3 * inch, y_position, f"+£{credit:.2f}")
    c.drawRightString(7 * inch, y_position, f"£{balance:.2f}")
    y_position -= 15

    # Rent payment
    debit = applicant['monthlyRent']
    balance -= debit
    c.drawString(1 * inch, y_position, f"10/{month[:3]}/{year}")
    c.drawString(2 * inch, y_position, "RENT PAYMENT - DIRECT DEBIT")
    c.drawRightString(5.3 * inch, y_position, f"-£{debit:.2f}")
    c.drawRightString(7 * inch, y_position, f"£{balance:.2f}")
    y_position -= 15

    # Random expenses
    expenses = [
        ("TESCO SUPERMARKET", random.randint(30, 80)),
        ("ELECTRICITY BILL", random.randint(50, 120)),
        ("COUNCIL TAX", random.randint(100, 150)),
        ("MOBILE PHONE", random.randint(15, 40)),
        ("TRANSPORT", random.randint(20, 60))
    ]

    for i, (desc, amount) in enumerate(expenses):
        if y_position < 2 * inch:
            break
        balance -= amount
        c.drawString(1 * inch, y_position, f"{12 + i}/{month[:3]}/{year}")
        c.drawString(2 * inch, y_position, desc)
        c.drawRightString(5.3 * inch, y_position, f"-£{amount:.2f}")
        c.drawRightString(7 * inch, y_position, f"£{balance:.2f}")
        y_position -= 15

    # Closing balance
    y_position -= 10
    c.line(1 * inch, y_position, 7 * inch, y_position)
    y_position -= 20
    c.setFont("Helvetica-Bold", 9)
    c.drawString(1 * inch, y_position, "Closing Balance")
    c.drawRightString(7 * inch, y_position, f"£{balance:.2f}")

    # Footer
    c.setFont("Helvetica", 7)
    c.drawString(1 * inch, 1 * inch, "This statement is computer generated and does not require a signature.")
    c.drawString(1 * inch, 0.8 * inch, "UK Banking Group is authorised by the Prudential Regulation Authority.")

    c.save()
    buffer.seek(0)
    return buffer


def create_id_document(applicant):
    """Generate passport-style ID document PDF"""
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4

    # Passport header (dark red background)
    c.setFillColorRGB(0.55, 0, 0)
    c.rect(0, height - 2 * inch, width, 2 * inch, fill=True, stroke=False)

    c.setFillColorRGB(1, 1, 1)
    c.setFont("Helvetica-Bold", 24)
    c.drawCentredString(width / 2, height - 1 * inch, "UNITED KINGDOM")
    c.setFont("Helvetica-Bold", 18)
    c.drawCentredString(width / 2, height - 1.4 * inch, "PASSPORT")

    # Photo placeholder
    c.setFillColorRGB(0.8, 0.8, 0.8)
    c.rect(1 * inch, height - 5 * inch, 1.5 * inch, 2 * inch, fill=True, stroke=True)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 8)
    c.drawCentredString(1.75 * inch, height - 4 * inch, "PHOTO")

    # Personal details
    c.setFont("Helvetica", 9)
    c.drawString(3 * inch, height - 3 * inch, "Surname:")
    c.setFont("Helvetica-Bold", 11)
    c.drawString(4 * inch, height - 3 * inch, applicant['lastName'].upper())

    c.setFont("Helvetica", 9)
    c.drawString(3 * inch, height - 3.4 * inch, "Given Names:")
    c.setFont("Helvetica-Bold", 11)
    c.drawString(4 * inch, height - 3.4 * inch, applicant['firstName'].upper())

    c.setFont("Helvetica", 9)
    c.drawString(3 * inch, height - 3.8 * inch, "Nationality:")
    c.setFont("Helvetica-Bold", 11)
    c.drawString(4 * inch, height - 3.8 * inch, "BRITISH CITIZEN")

    c.setFont("Helvetica", 9)
    c.drawString(3 * inch, height - 4.2 * inch, "Date of Birth:")
    c.setFont("Helvetica-Bold", 11)
    c.drawString(4 * inch, height - 4.2 * inch, applicant['dob'])

    c.setFont("Helvetica", 9)
    c.drawString(3 * inch, height - 4.6 * inch, "Place of Birth:")
    c.setFont("Helvetica-Bold", 11)
    c.drawString(4 * inch, height - 4.6 * inch, "LONDON, GBR")

    # Passport number and dates
    passport_num = ''.join([str(random.randint(0, 9)) for _ in range(9)])
    issue_date = (datetime.now() - timedelta(days=random.randint(365, 1825))).strftime("%d %b %Y")
    expiry_date = (datetime.now() + timedelta(days=random.randint(365, 3650))).strftime("%d %b %Y")

    c.setFont("Helvetica", 9)
    c.drawString(1 * inch, height - 6 * inch, f"Passport No: {passport_num}")
    c.drawString(1 * inch, height - 6.3 * inch, f"Date of Issue: {issue_date}")
    c.drawString(1 * inch, height - 6.6 * inch, f"Date of Expiry: {expiry_date}")

    # Machine readable zone
    c.setFont("Courier", 8)
    mrz1 = f"P<GBR{applicant['lastName'].upper().replace(' ', '<')}<<{applicant['firstName'].upper().replace(' ', '<')}<<<<<<<<<"[
           :44]
    mrz2 = f"{passport_num}<GBR{applicant['dob'].replace('-', '')}<M{expiry_date.replace(' ', '')}<<<<<<<<<"[:44]
    c.drawString(1 * inch, height - 7.5 * inch, mrz1)
    c.drawString(1 * inch, height - 7.7 * inch, mrz2)

    c.save()
    buffer.seek(0)
    return buffer


def create_tenancy_agreement(applicant):
    """Generate tenancy agreement PDF"""
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4

    c.setFont("Helvetica-Bold", 16)
    c.drawCentredString(width / 2, height - 1 * inch, "ASSURED SHORTHOLD TENANCY AGREEMENT")

    c.setFont("Helvetica", 10)
    y = height - 1.8 * inch

    lines = [
        f"This Agreement is made on {datetime.now().strftime('%d %B %Y')}",
        "",
        "BETWEEN:",
        "Landlord: Property Management Ltd, 123 Estate Road, London, SW1A 1AA",
        "",
        "AND:",
        f"Tenant: {applicant['firstName']} {applicant['lastName']}",
        f"Address: {applicant['address']['line1']}, {applicant['address']['city']}, {applicant['address']['postcode']}",
        "",
        "PROPERTY:",
        f"The property let is: {applicant['address']['line1']}, {applicant['address']['city']}, {applicant['address']['postcode']}",
        "",
        f"RENT: £{applicant['monthlyRent']:.2f} per calendar month",
        "Payment due: First day of each month",
        "Payment method: Standing Order",
        "",
        "TERM:",
        "Fixed term of 12 months commencing on the date above",
        "",
        "DEPOSIT:",
        f"£{applicant['monthlyRent'] * 1.5:.2f} held in approved tenancy deposit scheme",
        "",
        "TENANT OBLIGATIONS:",
        "1. To pay rent on time",
        "2. To keep property in good condition",
        "3. To allow landlord access for inspections with 24 hours notice",
        "4. Not to sublet without written permission",
        "",
        "LANDLORD OBLIGATIONS:",
        "1. To maintain property structure and exterior",
        "2. To ensure all safety certificates are current",
        "3. To protect tenant deposit in approved scheme",
        "4. To provide 24 hours notice before property inspections",
        "",
        "",
        "Signed by Landlord: _______________________   Date: __________",
        "",
        f"Signed by Tenant: {applicant['firstName']} {applicant['lastName']}   Date: {datetime.now().strftime('%d/%m/%Y')}"
    ]

    for line in lines:
        c.drawString(1 * inch, y, line)
        y -= 15
        if y < 1.5 * inch:
            c.showPage()
            y = height - 1 * inch

    c.save()
    buffer.seek(0)
    return buffer


# ═══════════════════════════════════════════════════════════════════════
# API SUBMISSION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

def submit_application(case_type, org_id):
    """Generate and submit full application to intake API"""

    print(f"\n{'=' * 60}")
    print(f"Generating {case_type} application for {org_id}")
    print('=' * 60)

    # Step 1: Generate profile
    print("📝 Generating applicant profile...")
    applicant = generate_applicant_profile(case_type, org_id)
    print(f"✓ Profile: {applicant['firstName']} {applicant['lastName']}")
    print(
        f"  Income: £{applicant['monthlyIncome']}, Savings: £{applicant['accountBalance']}, Rent: £{applicant['monthlyRent']}")

    # Generate case ID
    case_id = f"{org_id.upper()}-{datetime.now().year}-{random.randint(100000, 999999)}"

    # Create manifest
    manifest = {
        "caseId": case_id,
        "orgId": org_id,
        "caseType": case_type,
        "submissionType": "NEW",
        "applicant": {
            "firstName": applicant['firstName'],
            "lastName": applicant['lastName'],
            "dob": applicant['dob'],
            "nationalInsurance": applicant['nationalInsurance'],
            "email": applicant['email'],
            "phone": applicant['phone']
        },
        "documents-to-upload": [
            {"fileName": "id_proof.pdf", "documentType": "id_proof", "version": 1},
            {"fileName": "bank_jan_2026.pdf", "documentType": "bank_statement", "month": "January-2026", "version": 1},
            {"fileName": "bank_dec_2025.pdf", "documentType": "bank_statement", "month": "December-2025", "version": 1},
            {"fileName": "bank_nov_2025.pdf", "documentType": "bank_statement", "month": "November-2025", "version": 1},
            {"fileName": "tenancy.pdf", "documentType": "tenancy_agreement", "version": 1}
        ],
        "submittedAt": datetime.utcnow().isoformat() + "Z"
    }

    if DRY_RUN_MODE:
        print(f"\n🔵 DRY RUN MODE - Skipping API calls")
        print(f"  Would submit manifest: {json.dumps(manifest, indent=2)}")
        return {"success": True, "caseId": case_id, "dryRun": True}

    # Step 2: Initialize
    print(f"\n🔄 Step 1: POST /applications/init")
    try:
        headers = {"Content-Type": "application/json"}
        if API_AUTHORIZATION_TOKEN:
            headers["Authorization"] = API_AUTHORIZATION_TOKEN

        response = requests.post(
            f"{INTAKE_API_URL}/applications/init",
            json=manifest,
            headers=headers,
            timeout=30
        )

        if response.status_code != 200:
            print(f"✗ Failed to initialize: HTTP {response.status_code}")
            print(f"  Response: {response.text}")
            return {"success": False, "error": f"Init failed: {response.status_code}"}

        init_data = response.json()
        print(f"✓ Initialized: {init_data.get('caseId', case_id)}")
        presigned_urls = init_data.get('uploadUrls', {})

    except requests.exceptions.ConnectionError as e:
        print(f"✗ Connection error: Cannot reach {INTAKE_API_URL}")
        print(f"  Check your API URL and network connection")
        return {"success": False, "error": "Connection failed"}
    except Exception as e:
        print(f"✗ Failed to initialize: {e}")
        return {"success": False, "error": str(e)}

    # Step 3: Generate and upload documents
    print(f"\n📄 Step 2: Generating and uploading documents")

    documents = {
        'id_proof': create_id_document(applicant),
        'bank_statement_jan': create_bank_statement(applicant, "January", "2026"),
        'bank_statement_dec': create_bank_statement(applicant, "December", "2025"),
        'bank_statement_nov': create_bank_statement(applicant, "November", "2025"),
        'tenancy_agreement': create_tenancy_agreement(applicant)
    }

    # Save local copies if requested
    if SAVE_PDFS_LOCALLY:
        import os
        os.makedirs(LOCAL_PDF_PATH, exist_ok=True)
        for doc_type, doc_buffer in documents.items():
            filepath = f"{LOCAL_PDF_PATH}/{case_id}_{doc_type}.pdf"
            doc_buffer.seek(0)
            with open(filepath, 'wb') as f:
                f.write(doc_buffer.read())
            doc_buffer.seek(0)
            print(f"  💾 Saved: {filepath}")

    # Upload documents
    upload_success = True
    for doc_type, doc_buffer in documents.items():
        if doc_type in presigned_urls:
            try:
                doc_buffer.seek(0)
                upload_response = requests.put(
                    presigned_urls[doc_type],
                    data=doc_buffer.read(),
                    # No Content-Type header: presigned URL sig does not include it
                    # Adding it causes SignatureDoesNotMatch 403
                    timeout=30
                )

                if upload_response.status_code == 200:
                    print(f"  ✓ Uploaded {doc_type}.pdf")
                else:
                    print(f"  ✗ Failed to upload {doc_type}: HTTP {upload_response.status_code}")
                    upload_success = False

            except Exception as e:
                print(f"  ✗ Failed to upload {doc_type}: {e}")
                upload_success = False
        else:
            print(f"  ⚠️  No presigned URL for {doc_type}")

    if not upload_success:
        print(f"⚠️  Some documents failed to upload")

    # Step 4: Finalize
    print(f"\n✅ Step 3: POST /applications/complete")
    try:
        response = requests.post(
            f"{INTAKE_API_URL}/applications/complete",
            json={"caseId": case_id},
            headers=headers,
            timeout=30
        )

        if response.status_code == 200:
            print(f"✓ Application finalized!")
            print(f"✓ Status: INTAKE_VALIDATED")
            print(f"✓ Case ID: {case_id}")
            return {"success": True, "caseId": case_id, "status": "INTAKE_VALIDATED"}
        else:
            print(f"✗ Failed to finalize: HTTP {response.status_code}")
            print(f"  Response: {response.text}")
            return {"success": False, "error": f"Finalize failed: {response.status_code}"}

    except Exception as e:
        print(f"✗ Failed to finalize: {e}")
        return {"success": False, "error": str(e)}


# ═══════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════

def validate_configuration():
    """Check configuration before running"""
    errors = []

    if INTAKE_API_URL == "CHANGE_ME_TO_YOUR_API_URL":
        errors.append("⚠️  INTAKE_API_URL not configured")
        errors.append("   Edit the script and set your API Gateway URL")

    if not INTAKE_API_URL.startswith("https://"):
        errors.append("⚠️  INTAKE_API_URL should start with https://")

    if errors:
        print("\n" + "=" * 60)
        print("CONFIGURATION ERRORS")
        print("=" * 60)
        for error in errors:
            print(error)
        print("\nPlease fix the configuration and try again.")
        print("=" * 60 + "\n")
        return False

    return True


if __name__ == "__main__":

    # Validate configuration
    if not validate_configuration():
        sys.exit(1)

    print("╔" + "=" * 58 + "╗")
    print("║" + " " * 15 + "TEST DATA GENERATOR" + " " * 23 + "║")
    print("╚" + "=" * 58 + "╝")

    if DRY_RUN_MODE:
        print("\n🔵 Running in DRY RUN mode - no API calls will be made")

    if SAVE_PDFS_LOCALLY:
        print(f"\n💾 Saving PDFs locally to: {LOCAL_PDF_PATH}")

    print(f"\n🎯 Target API: {INTAKE_API_URL}")
    print("")

    # Define test cases
    # Format: (case_type, org_id)
    test_cases = [
        ("hardship-fund", "councilA"),
        ("housing-support", "councilB"),
    ]

    print(f"📊 Will generate {len(test_cases)} test applications\n")

    successful = 0
    failed = 0
    case_ids = []

    for i, (case_type, org_id) in enumerate(test_cases, 1):
        print(f"\n\n{'#' * 60}")
        print(f"# TEST APPLICATION {i}/{len(test_cases)}")
        print(f"{'#' * 60}")

        result = submit_application(case_type, org_id)

        if result.get('success'):
            successful += 1
            case_ids.append(result.get('caseId'))
        else:
            failed += 1

    # Summary
    print(f"\n\n{'=' * 60}")
    print("GENERATION COMPLETE")
    print('=' * 60)
    print(f"✅ Successful: {successful}")
    print(f"❌ Failed: {failed}")
    print(f"📊 Total: {len(test_cases)}")

    if case_ids:
        print(f"\n📋 Generated Case IDs:")
        for case_id in case_ids:
            print(f"  • {case_id}")

    if SAVE_PDFS_LOCALLY:
        print(f"\n💾 PDFs saved to: {LOCAL_PDF_PATH}")

    print('=' * 60 + "\n")

    # Next steps
    if successful > 0:
        print("✅ NEXT STEPS:")
        print("  1. Check DynamoDB → case_runtime_state table")
        print("  2. Verify S3 → validated-application-intake bucket")
        print("  3. Check EventBridge → event history")
        print("  4. Monitor Step Functions → workflow executions")
        print("")

if __name__ == "__main__":
    print("=" * 60)
    print("CONFIGURATION CHECK")
    print("=" * 60)
    print(f"API URL: {INTAKE_API_URL}")
    print(f"Test cases to generate: {len(test_cases)}")
    print("")

    # Test profile generation
    print("Testing profile generation...")
    profile = generate_applicant_profile("hardship-fund", "councilA")
    print(f"✓ Generated profile for: {profile['firstName']} {profile['lastName']}")
    print(f"  NI Number: {profile['nationalInsurance']}")
    print(f"  Income: £{profile['monthlyIncome']}")
    print(f"  Savings: £{profile['accountBalance']}")
    print("")
    print("Configuration looks good! Remove this test code to proceed.")