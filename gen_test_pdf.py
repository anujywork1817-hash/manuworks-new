from fpdf import FPDF

class PDF(FPDF):
    def header(self):
        self.set_font("Helvetica", "B", 9)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, "DOCASSIST TEST DOCUMENT  |  CONFIDENTIAL", align="R")
        self.ln(2)
        self.set_draw_color(180, 180, 180)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(4)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(150, 150, 150)
        self.cell(0, 10, f"Page {self.page_no()}", align="C")

    def h1(self, text):
        self.set_font("Helvetica", "B", 15)
        self.set_text_color(15, 23, 42)
        self.ln(4)
        self.cell(0, 10, text, align="C")
        self.ln(10)

    def h2(self, text):
        self.set_font("Helvetica", "B", 12)
        self.set_text_color(67, 56, 202)
        self.ln(3)
        self.cell(0, 7, text)
        self.ln(7)

    def h3(self, text):
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(30, 30, 80)
        self.cell(0, 6, text)
        self.ln(6)

    def body(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(30, 30, 30)
        self.multi_cell(190, 6, text)
        self.ln(2)

    def bullet(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(30, 30, 30)
        self.cell(6, 6, "-")
        self.multi_cell(184, 6, text)

    def label(self, key, val):
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(80, 80, 80)
        self.cell(50, 6, key)
        self.set_font("Helvetica", "", 10)
        self.set_text_color(20, 20, 20)
        self.multi_cell(140, 6, val)

    def divider(self):
        self.ln(2)
        self.set_draw_color(200, 200, 200)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(4)

pdf = PDF()
pdf.set_margins(10, 15, 10)
pdf.set_auto_page_break(True, margin=18)
pdf.add_page()

# ── TITLE ────────────────────────────────────────────────────────────────────
pdf.set_font("Helvetica", "B", 16)
pdf.set_text_color(15, 23, 42)
pdf.cell(190, 10, "SERVICE AGREEMENT CUM NON-DISCLOSURE DEED", align="C")
pdf.ln(10)
pdf.set_font("Helvetica", "", 10)
pdf.set_text_color(100, 100, 100)
pdf.cell(190, 6, "Apex Technologies Pvt. Ltd.  vs.  Rajesh Kumar Sharma", align="C")
pdf.ln(6)
pdf.set_font("Helvetica", "I", 9)
pdf.cell(190, 6, "Executed at Mumbai, Maharashtra  |  Dated: 15th January 2024", align="C")
pdf.ln(6)
pdf.divider()

# ── PARTIES ───────────────────────────────────────────────────────────────────
pdf.h2("1.  PARTIES TO THE AGREEMENT")
pdf.label("Employer:", "Apex Technologies Pvt. Ltd., incorporated under Companies Act 2013 (CIN: U72900MH2010PTC208432), 14th Floor, One BKC Tower, Bandra Kurla Complex, Mumbai - 400 051, represented by Director Ms. Priya Mehta ('the Company').")
pdf.ln(2)
pdf.label("Employee:", "Mr. Rajesh Kumar Sharma, S/o Shri Mohan Lal Sharma, aged 34 years, Flat No. 402, Shree Apartments, Andheri East, Mumbai - 400 069, Aadhaar No. XXXX-XXXX-7824 ('the Employee').")
pdf.divider()

# ── RECITALS ─────────────────────────────────────────────────────────────────
pdf.h2("2.  RECITALS AND BACKGROUND")
pdf.body("WHEREAS the Company is engaged in software development, IT consulting, and technology solutions for banking, insurance, and e-commerce sectors in India and abroad; AND WHEREAS the Employee has represented that he possesses the requisite qualifications and experience in software architecture and cloud computing necessary for the position of Senior Software Architect; AND WHEREAS the Company, relying upon such representations, has agreed to employ the Employee on the terms and conditions hereinafter set forth; AND WHEREAS it is necessary to protect confidential information, intellectual property, and trade secrets; NOW THEREFORE, in consideration of mutual covenants herein contained, the parties agree as follows:")
pdf.divider()

# ── TIMELINE ─────────────────────────────────────────────────────────────────
pdf.h2("3.  EMPLOYMENT TIMELINE AND KEY DATES")
pdf.h3("3.1  Chronological Record of Events")
events = [
    ("01 Sep 2021",  "Employee applied via LinkedIn. Application reference: APX/2021/HR/4421."),
    ("15 Sep 2021",  "Technical interview conducted by CTO Mr. Arun Nair. Three rounds cleared."),
    ("28 Sep 2021",  "Background verification completed by Authbridge India Pvt. Ltd. No adverse findings."),
    ("10 Oct 2021",  "Offer Letter No. APEX/HR/OL/2021/887 issued; accepted by Employee on 12 Oct 2021."),
    ("01 Nov 2021",  "Date of Joining as Associate Software Architect, Grade B3."),
    ("01 Nov 2022",  "Annual appraisal. Promoted to Software Architect, Grade A2. Increment: 22%."),
    ("15 Mar 2023",  "Employee deputed to Singapore (DBS Bank) under Global Mobility Policy for 6 months."),
    ("14 Sep 2023",  "Deputation concluded. Employee returned to Mumbai office."),
    ("01 Nov 2023",  "Second appraisal. Designated Senior Software Architect, Grade A1. Increment: 18%."),
    ("15 Jan 2024",  "Present Agreement executed superseding all prior letters and communications."),
    ("31 Mar 2024",  "Probation confirmation deadline for responsibilities under this Agreement."),
    ("14 Jul 2024",  "ESOP Vesting - Tranche 1 (500 units) under APEX ESOP Plan 2021."),
    ("01 Jan 2025",  "Non-compete obligation review date; parties to negotiate extension if consented."),
    ("31 Oct 2025",  "Mandatory return of all Company assets and data on cessation of employment."),
]
for date, desc in events:
    pdf.set_font("Helvetica", "B", 10)
    pdf.set_text_color(67, 56, 202)
    pdf.cell(32, 6, date + ":")
    pdf.set_font("Helvetica", "", 10)
    pdf.set_text_color(30, 30, 30)
    pdf.multi_cell(158, 6, desc)
pdf.divider()

# ── COMPENSATION ──────────────────────────────────────────────────────────────
pdf.h2("4.  COMPENSATION, BENEFITS AND PERQUISITES")
pdf.body("The Employee shall be entitled to a Cost to Company (CTC) of INR 38,00,000 (Rupees Thirty-Eight Lakhs Only) per annum, structured as under:")
comp = [
    ("Basic Salary:",           "INR 15,20,000 (40% of CTC)"),
    ("HRA:",                    "INR 7,60,000 (50% of Basic; exempt u/s 10(13A) IT Act)"),
    ("Special Allowance:",      "INR 5,00,000 per annum"),
    ("LTA:",                    "INR 1,20,000 (exempt u/s 10(5) for 2 journeys in 4 years)"),
    ("Medical:",                "INR 30,000 per annum (exempt up to INR 15,000 u/s 17(2))"),
    ("PF - Employer:",          "INR 1,82,400 (12% of Basic; u/s 80C deductible)"),
    ("Gratuity Provision:",     "INR 73,077 (per Payment of Gratuity Act, 1972)"),
    ("Performance Bonus:",      "Up to 15% of CTC, payable April, subject to KRA achievement"),
    ("ESOPs:",                  "2,000 units at INR 100 strike price; vesting over 4 years"),
]
for k, v in comp:
    pdf.label(k, v)
pdf.divider()

# ── DUTIES ───────────────────────────────────────────────────────────────────
pdf.h2("5.  DUTIES, RESPONSIBILITIES AND KEY PERFORMANCE AREAS")
pdf.h3("5.1  Primary Duties")
duties = [
    "Design and maintain enterprise-grade cloud architecture on AWS (EC2, RDS, Lambda, S3, CloudFront) and Azure.",
    "Lead a team of 8-12 engineers; conduct weekly sprints and bi-weekly code reviews.",
    "Prepare and present technical proposals and architecture design documents (ADD) to CTO and clients.",
    "Ensure compliance with ISO 27001:2013 information security standards and CERT-In guidelines.",
    "Coordinate with legal and compliance teams for data localisation obligations under the DPDP Act, 2023.",
    "Mentor junior engineers and conduct quarterly internal training sessions on cloud-native development.",
    "Provide availability (on-call) every alternate weekend; compensated per Company on-call policy.",
    "Travel domestically or internationally as required with minimum 48-hour advance notice.",
]
for d in duties:
    pdf.bullet(d)
pdf.ln(2)
pdf.h3("5.2  Key Result Areas (KRAs)")
kras = [
    ("System Uptime:", "99.9% SLA compliance for all production systems under Employee's architecture."),
    ("Cost Optimisation:", "Reduce cloud infrastructure cost by minimum 10% YoY without degrading performance."),
    ("Delivery Quality:", "Zero critical defect escapes; not more than 2 high-severity incidents per quarter."),
    ("Team Capability:", "Minimum 2 team members to clear AWS Solutions Architect certification per year."),
    ("Documentation:", "100% architecture documentation currency maintained in Confluence."),
]
for k, v in kras:
    pdf.label(k, v)
pdf.divider()

# ── CONFIDENTIALITY ───────────────────────────────────────────────────────────
pdf.h2("6.  NON-DISCLOSURE AND CONFIDENTIALITY OBLIGATIONS")
pdf.body("The Employee acknowledges that in the course of employment he will have access to information that is proprietary, confidential, and commercially sensitive, including but not limited to: source code, algorithms, product roadmaps, client data, pricing strategies, financial projections, unpublished patent applications, and business strategies of the Company and its clients ('Confidential Information').")
pdf.body("The Employee covenants and undertakes that:")
nda = [
    "He shall not, during or after employment, disclose Confidential Information to any third party without prior written consent of the CEO.",
    "He shall use Confidential Information solely for the Company's business and not for personal benefit or benefit of any competitor.",
    "Upon termination, he shall immediately return all documents, devices, and credentials. Failure within 7 days attracts liquidated damages of INR 5,00,000.",
    "Breach of confidentiality entitles the Company to seek injunctive relief from competent courts without establishing actual damage.",
    "These obligations shall survive termination for a period of 5 (five) years.",
]
for n in nda:
    pdf.bullet(n)
pdf.ln(2)
pdf.divider()

# ── LEGAL CITATIONS ──────────────────────────────────────────────────────────
pdf.h2("7.  APPLICABLE LAWS AND JUDICIAL PRECEDENTS")
pdf.h3("7.1  Statutory Framework")
statutes = [
    "The Industrial Disputes Act, 1947 (Sections 2(s), 25F, 25G, 25H) - termination and retrenchment.",
    "The Shops and Establishments Act (Maharashtra), 2017 - working hours, leave, conditions of service.",
    "The Payment of Gratuity Act, 1972 (Section 4) - gratuity payable after 5 years continuous service.",
    "The Employees' Provident Funds and Miscellaneous Provisions Act, 1952 (Section 6) - PF contributions.",
    "The Information Technology (Amendment) Act, 2008 (Sections 43A, 72A) - data privacy obligations.",
    "The Digital Personal Data Protection Act, 2023 - obligations as a 'Significant Data Fiduciary'.",
    "The Indian Contract Act, 1872 (Sections 27, 73, 74) - non-compete enforceability and liquidated damages.",
    "The Trade Marks Act, 1999 and Copyright Act, 1957 - intellectual property ownership.",
    "The Sexual Harassment of Women at Workplace Act, 2013 (POSH Act).",
    "The Companies Act, 2013 (Section 188) - related party transaction disclosures.",
]
for s in statutes:
    pdf.bullet(s)
pdf.ln(2)
pdf.h3("7.2  Relevant Judicial Precedents")
cases = [
    ("Niranjan Shankar Golikari v. Century Spinning Co., AIR 1967 SC 1098",
     "Upheld negative covenant restraining employee during service period. Enforceable as reasonable in time, geography, and trade."),
    ("Superintendence Co. of India v. Krishan Murgai, (1980) 2 SCC 175",
     "Post-employment non-compete clauses are void under Section 27, Indian Contract Act, unless within statutory exceptions."),
    ("Wipro Ltd. v. Beckman Coulter International SA, 2006 (3) Arb. LR 118 (Del. HC)",
     "Arbitration clause in employment valid; injunction granted restraining trade secret disclosure pending arbitration."),
    ("Gujarat Bottling Co. Ltd. v. Coca Cola Co., (1995) 5 SCC 545",
     "Negative covenants during subsistence of contract are enforceable; Section 27 applies only post-termination."),
    ("Percept D'Mark (India) v. Zaheer Khan, (2006) 4 SCC 227",
     "Post-termination non-compete held void as unreasonable restraint of trade under Indian Contract Act."),
    ("Desiccant Rotors International v. Bappaditya Sarkar, 152 (2008) DLT 56 (Del. HC)",
     "Duty of confidence survives termination; injunction upheld against disclosure of confidential technical information."),
]
for citation, summary in cases:
    pdf.set_font("Helvetica", "BI", 10)
    pdf.set_text_color(67, 56, 202)
    pdf.multi_cell(190, 6, citation)
    pdf.set_font("Helvetica", "", 10)
    pdf.set_text_color(50, 50, 50)
    pdf.multi_cell(190, 6, "   " + summary)
    pdf.ln(1)
pdf.divider()

# ── RISKS ─────────────────────────────────────────────────────────────────────
pdf.h2("8.  RISK FACTORS, LIABILITIES AND PENALTIES")
pdf.h3("8.1  Risks to the Company")
risks_co = [
    "Data breach by Employee: penalties up to INR 250 Crore under DPDP Act 2023 (Section 25) and criminal liability under IT Act Section 43A.",
    "Non-compliance with PF/ESI deductions: prosecution under EPF Act Section 14 (imprisonment up to 3 years and fine).",
    "Improper ESOP documentation may attract SEBI scrutiny under SEBI (Share Based Employee Benefits) Regulations, 2021.",
    "Failure to issue Form 16 on time: penalty INR 100 per day under Section 272A(2)(g), Income Tax Act, 1961.",
    "Non-compliance with POSH Act (IC, Annual Report): fine up to INR 50,000 and possible licence cancellation.",
]
for r in risks_co:
    pdf.bullet(r)
pdf.ln(2)
pdf.h3("8.2  Risks to the Employee")
risks_emp = [
    "Violation of NDA: liquidated damages INR 5,00,000 plus actual damages as proved by the Company.",
    "Joining competitor within 12 months without NoC: forfeiture of unvested ESOPs (1,500 units, market value approx. INR 15,00,000).",
    "False representation of qualifications: constitutes fraud under IPC Section 420; grounds for summary dismissal.",
    "Failure to disclose conflict of interest: civil liability under Companies Act 2013.",
    "Unauthorised copying of source code: offence under IT Act Section 66B (imprisonment up to 3 years) and Copyright Act Sections 63-65.",
]
for r in risks_emp:
    pdf.bullet(r)
pdf.divider()

# ── ACTION ITEMS ──────────────────────────────────────────────────────────────
pdf.h2("9.  ACTION ITEMS AND COMPLIANCE CHECKLIST")
pdf.h3("9.1  Immediate Actions (Within 7 Days of Execution)")
immediate = [
    "Employee to submit original educational certificates (B.Tech, M.Tech, AWS certs) to HR for verification.",
    "Employee to provide updated address proof, PAN card, Aadhaar, and cancelled cheque for salary disbursement.",
    "HR to enrol Employee in Group Medical Insurance (floater cover INR 5 lakhs) with ICICI Lombard.",
    "IT department to issue laptop (Dell XPS 15), access badge, email credentials, and VPN certificates.",
    "Employee to complete mandatory e-learning on POSH Policy, IT Security Policy, and Code of Conduct on LMS.",
    "Finance to update payroll in SAP HCM system effective 01 February 2024.",
    "Legal team to file stamp duty payment for this Agreement with Sub-Registrar, Mumbai.",
]
for a in immediate:
    pdf.bullet(a)
pdf.ln(2)
pdf.h3("9.2  Monthly and Quarterly Actions")
periodic = [
    "HR to issue monthly salary slips by 5th of following month.",
    "Employee to submit travel expense claims within 15 days of travel.",
    "Employee to complete timesheet in Jira by last working day of every month.",
    "Quarterly performance review meeting between Employee and CTO.",
    "Semi-annual declaration of outside interests / conflict of interest form.",
    "ESOP vesting schedule to be confirmed in writing by Finance on each vesting date.",
]
for a in periodic:
    pdf.bullet(a)
pdf.divider()

# ── DEADLINES ─────────────────────────────────────────────────────────────────
pdf.h2("10.  CRITICAL DEADLINES AND NOTICE PERIODS")
deadlines = [
    ("Notice (Resignation):", "90 days written notice; Company may waive and pay in lieu."),
    ("Notice (Termination):", "90 days or salary in lieu; except summary dismissal for misconduct."),
    ("Gratuity Payment:", "Within 30 days of cessation (Payment of Gratuity Act 1972, Section 7)."),
    ("Full & Final Settlement:", "Within 60 days of last working day including reimbursements and leave encashment."),
    ("ESOP Exercise Window:", "180 days from vesting date; options lapse if not exercised within window."),
    ("Garden Leave Expiry:", "14 July 2024 - earliest date Employee may join a competitor post-resignation."),
    ("Asset Return Deadline:", "All Company assets returned within 7 days of last working day."),
    ("Non-Compete Review:", "01 January 2025 - parties to meet and renegotiate scope."),
    ("PF Transfer Deadline:", "60 days of joining to initiate PF transfer from prior employer."),
    ("Income Tax Form 12BB:", "Submit investment declaration by 15th April every financial year."),
    ("Annual Performance Review:", "31 October each year; increment effective 01 November."),
    ("POSH Annual Report:", "31 January each year - IC to submit report to District Officer."),
]
for d, v in deadlines:
    pdf.label(d, v)
pdf.divider()

# ── TERMINATION ───────────────────────────────────────────────────────────────
pdf.h2("11.  TERMINATION AND POST-EMPLOYMENT OBLIGATIONS")
pdf.h3("11.1  Grounds for Summary Termination (Without Notice)")
grounds = [
    "Proven dishonesty, fraud, or misappropriation of Company assets or funds.",
    "Serious misconduct including sexual harassment, violence, or intimidation.",
    "Unauthorised disclosure of trade secrets or Confidential Information.",
    "Conviction of a criminal offence involving moral turpitude.",
    "Prolonged absence without leave (more than 10 consecutive working days).",
    "Material misrepresentation of qualifications, experience, or identity during recruitment.",
    "Breach of Information Security Policy resulting in a reportable data incident.",
]
for g in grounds:
    pdf.bullet(g)
pdf.ln(2)
pdf.h3("11.2  Post-Employment Restrictions (12 Months)")
restrictions = [
    "Shall not solicit any client of the Company with whom Employee had dealings in the 24 months preceding termination.",
    "Shall not induce or attempt to induce any employee of the Company to leave.",
    "Shall not engage in same or similar line of business within the territorial limits of India and Singapore.",
    "Shall not use the Company's name, logos, or any Confidential Information for any commercial purpose.",
]
for r in restrictions:
    pdf.bullet(r)
pdf.body("PROVIDED HOWEVER that restriction (iii) above shall be limited to 6 months in light of Superintendence Company of India v. Krishan Murgai (supra) and shall not apply to activities unrelated to cloud architecture or fintech software.")
pdf.divider()

# ── DISPUTE RESOLUTION ────────────────────────────────────────────────────────
pdf.h2("12.  DISPUTE RESOLUTION AND JURISDICTION")
pdf.body("Any dispute arising out of this Agreement shall be first referred to mediation under MCIA. If not resolved within 30 days, it shall be settled by arbitration under the Arbitration and Conciliation Act, 1996 (as amended in 2019). The seat of arbitration shall be Mumbai. The award shall be final and binding.")
pdf.body("Either party may seek urgent interim relief (including injunction) from Courts at Mumbai, which shall have exclusive jurisdiction, to the exclusion of all other courts.")
pdf.divider()

# ── GENERAL (grammar test embedded) ─────────────────────────────────────────
pdf.h2("13.  GENERAL PROVISIONS AND MISCELLANEOUS TERMS")
# intentional grammar issues for 'Grammar Check' feature testing:
pdf.body("This Agreement shall be construed in accordance with the laws of India. The parties have agreed, declared, and confirm that this Agreement supersedes all previous communications, understandings, or agreements-whether oral or written-between the parties. There are no representation, warranties, or conditions other than those expressly set out in this Agreement. No modification or amendment shall be valid unless made in writing and signed by authorised representative of both parties. If any provision is found invalid or unenforceable, the remaining provisions shall continue in full force. Each party represents that they has capacity to enter into this Agreement, has read and understands all its terms, and has sought independent legal advise prior to signing.")
pdf.body("This Agreement is executed in duplicate, each of which shall constitute an original. Stamp duty of INR 500 shall be paid on one original per Maharashtra Stamp Act, 1958 (Article 36). Both originals shall be retained-one by the Company and one by the Employee.")
pdf.divider()

# ── SIGNATURES ────────────────────────────────────────────────────────────────
pdf.h2("14.  EXECUTION AND SIGNATURES")
pdf.ln(4)
pdf.set_font("Helvetica", "", 10)
pdf.set_text_color(30, 30, 30)
pdf.cell(95, 6, "For Apex Technologies Pvt. Ltd.")
pdf.cell(0, 6, "Employee")
pdf.ln(16)
pdf.set_draw_color(80, 80, 80)
pdf.line(12, pdf.get_y(), 95, pdf.get_y())
pdf.line(110, pdf.get_y(), 195, pdf.get_y())
pdf.ln(4)
pdf.cell(95, 6, "Ms. Priya Mehta, Director")
pdf.cell(0, 6, "Mr. Rajesh Kumar Sharma")
pdf.ln(6)
pdf.cell(95, 6, "Date: ___________________")
pdf.cell(0, 6, "Date: ___________________")
pdf.ln(6)
pdf.cell(95, 6, "Place: Mumbai")
pdf.cell(0, 6, "Place: Mumbai")
pdf.divider()

# ── SCHEDULE A: SUMMARY ───────────────────────────────────────────────────────
pdf.h2("SCHEDULE A: EXECUTIVE SUMMARY")
pdf.body(
    "Parties:           Apex Technologies Pvt. Ltd. (Company) and Rajesh Kumar Sharma (Employee)\n"
    "Role:              Senior Software Architect, Grade A1\n"
    "CTC:               INR 38,00,000 per annum (effective 01 November 2023)\n"
    "Notice Period:     90 days (both sides)\n"
    "Non-Compete:       12 months post-employment (India + Singapore)\n"
    "NDA Duration:      5 years post-employment\n"
    "Governing Law:     Laws of India; Jurisdiction: Mumbai Courts\n"
    "Dispute:           MCIA Mediation then Arbitration (Arbitration Act 1996)\n"
    "Key Risk:          Breach of NDA - INR 5 lakh liquidated damages + injunction\n"
    "ESOP:              2,000 units over 4 years; Tranche 1 (500 units) on 14 July 2024"
)
pdf.divider()

# ── SCHEDULE B: TAGS ──────────────────────────────────────────────────────────
pdf.h2("SCHEDULE B: CLASSIFICATION AND TAGS")
pdf.body(
    "Document Type:     Employment Agreement / Service Agreement / NDA\n"
    "Industry:          Information Technology / Software Services\n"
    "Jurisdiction:      India (Maharashtra)\n"
    "Acts Referenced:   Indian Contract Act 1872, IT Act 2000, DPDP Act 2023, Companies Act 2013, EPF Act 1952, Gratuity Act 1972, POSH Act 2013, Copyright Act 1957, Arbitration Act 1996, Maharashtra Stamp Act 1958\n"
    "Parties:           Technology Company (Employer); Senior Technical Professional (Employee)\n"
    "Sensitivity:       Confidential - HR and Legal\n"
    "Retention Policy:  10 years post-termination\n"
    "Tags:              employment, NDA, non-compete, ESOP, cloud, software, Mumbai, Maharashtra, arbitration, MCIA, confidentiality, gratuity, PF, POSH, DPDP, IT-Act, salary, appraisal, termination, data-protection"
)

out = r"c:\manuworks\DocAssist_Test_Document.pdf"
pdf.output(out)
print(f"PDF saved: {out}")
print(f"Pages: {pdf.page}")
