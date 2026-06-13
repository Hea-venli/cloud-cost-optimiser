# Cloud Cost Optimiser

A tool that checks my AWS account every day for things that waste money, it also saves a report, and emails me a summary. It runs by itself on a schedule, It runs on a schedule with no manual involvement.

## Where's the code?

| File | What it does |
|------|--------------|
| [`main.tf`](main.tf) | All the AWS infrastructure as Terraform code |
| [`src/lambda_function.py`](src/lambda_function.py) | The Python scanner (runs the 3 cost checks) |

## The problem

Cloud accounts quietly waste money on things people forget about, such as storage left behind, servers switched off but still charging, and resources nobody labelled so nobody cleans them up. This tool finds them automatically.

## What it checks

- **Unattached storage** — disks left behind, still being charged for
- **Stopped servers** — switched off, but storage still costs money
- **Untagged servers** — no label = nobody owns it = never cleaned up

## How it works

![Architecture diagram](architecture.png)

1. A timer (EventBridge) wakes the tool up once a day
2. The tool (a Lambda function written in Python) checks the account
3. It saves a dated report to storage (S3)
4. It emails me a summary (SNS)
5. Then it switches off until tomorrow

## What I used

- **AWS Lambda** — runs my Python code
- **EventBridge** — the daily timer
- **S3** — stores the reports
- **SNS** — sends the email
- **IAM** — controls what the tool is allowed to do
- **Terraform** — lets me rebuild the whole thing from code

## Choices I made

**I used Lambda instead of a server.** The job takes about 2 seconds a day. A normal server would cost money all day doing nothing. Lambda only runs when needed and costs almost nothing.

**I gave the tool least privilege.** It can only save a report and send an email, nothing else. So even if something went wrong, it couldn't do any damage.

**I set a 30-second time limit.** The job normally takes 2 seconds, so if it ever takes longer than 30, something's wrong and it stops itself instead of running up a bill.

**I kept the storage private.** The reports are internal, so nobody outside can see them. They're saved with the date in the name, so each day's report is kept instead of being overwritten.

## It working

**The daily email summary I receive:**

![Daily email](screenshots/daily-email.png)

**The Lambda function running successfully:**

![Successful run](screenshots/lambda-success-1.png)
![Lambda success 2](screenshots/lambda-success-2.png)

**Reports saved in S3, one per day:**

![S3 reports](screenshots/s3-reports.png)

**The whole project built as code (Terraform):**

![Terraform state list](screenshots/terraform-state.png)

## What I learned

This was my first hands on AWS project after passing my Solutions Architect Associate exam. I learned how to read errors instead of fearing them, and how to rebuild my whole project from code using Terraform.

## Why build this? (AWS already has tools for this)

AWS already offers a lot here:

- **Cost Explorer** shows spend, and can break it down by tags.
- **Trusted Advisor** flags some idle and underused resources.
- **CloudWatch** monitors performance and can raise alarms.

I built this **to learn AWS by doing**, not just by passing an exam.

Re-creating a slice of this functionality myself meant designing the whole **backend** from scratch — wiring together Lambda, IAM (least-privilege), S3, SNS, EventBridge and Terraform into one automated system. Building a backend that runs on a schedule, handles permissions safely, stores its own reports and reports failures teaches you things an exam never will — especially when something breaks and you have to fix it.

That hands-on backend understanding is the point of this project.

## What I'd add next

- Handle very large accounts
- Show the estimated monthly saving for each finding
- Check storage and other resources for missing labels too
