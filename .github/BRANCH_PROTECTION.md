# GitHub Branch Protection Setup

This document explains how to configure GitHub to require tests to pass and your approval before merging PRs using GitHub Rulesets (the modern approach as of 2024-2025).

## 1. Add Repository Secrets

1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add these secrets:
   - Name: `ANTHROPIC_API_KEY`, Value: your Anthropic API key
   - Name: `MISTRAL_API_KEY`, Value: your Mistral API key

## 2. Create a Branch Ruleset

### Step 1: Navigate to Rulesets
1. Go to your repository **Settings**
2. In left sidebar: **Rules** → **Rulesets**
3. Click **New ruleset** → **New branch ruleset**

### Step 2: Configure Ruleset Basics
1. **Ruleset Name:** Enter "Protect main branch"
2. **Enforcement status:** Select **Active**

### Step 3: Set Target Branches
1. Click **Add a target**
2. Select **Include by pattern**
3. Enter pattern: `main` (or `master` if that's your default branch)

### Step 4: Configure Branch Protections

**Required settings:**

1. **Require a pull request before merging**
   - Check this box
   - Set **Required approvals** to **1**
   - This ensures you must approve all PRs before they can merge

2. **Require status checks to pass**
   - Check this box
   - Click **Add checks**
   - In the search box, type: `R-CMD-check`
   - Click the + icon to add it
   - Check **Require branches to be up to date before merging**

   Note: The check name `R-CMD-check` must match the workflow job name. It will only appear after the workflow runs at least once.

**Optional but recommended:**
- **Require conversation resolution before merging** - Ensures all PR comments are addressed
- **Require signed commits** - Extra security
- **Require linear history** - Keeps git history clean (no merge commits)

### Step 5: Save Ruleset
1. Click **Create**
2. Ruleset is now active and enforced immediately

## 3. Workflow Behavior

The workflow (`R-CMD-check.yaml`) runs:
- **When:** Pull request is opened or updated targeting `main`
- **What:** Runs full test suite with real API calls using repository secrets
- **Result:** PR can only merge if:
  1. All tests pass (green checkmark)
  2. You approve the PR

## 4. Working with Protected Branches

### Creating a PR

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes and commit
git add .
git commit -m "Add new feature"

# Push to GitHub
git push origin feature/my-feature
```

### On GitHub
1. Open pull request to `main`
2. Tests run automatically
3. Wait for results:
   - Green checkmark = tests passed
   - Red X = tests failed (must fix before merging)
4. You review and approve the PR
5. Once both tests pass AND you approve, "Merge pull request" becomes available

### Merging Requirements Checklist
- [ ] Tests passed (R-CMD-check green)
- [ ] You approved the PR
- [ ] All conversations resolved (if enabled)
- [ ] Branch is up to date (if enabled)

Only when all requirements are met can the PR be merged.

## 5. Viewing Test Results

- On PR page, click **Checks** tab
- See detailed test output
- Click **Details** next to R-CMD-check to see full logs
- Review any failures and fix before re-pushing

## 6. Local Testing Before Pushing

To avoid failing tests in CI:

```r
# Load your .env file with API keys
ecoextract::load_env_file()

# Run tests locally
devtools::test()

# Check package
devtools::check()
```

Only push/create PR when local tests pass.

## 7. First-Time Setup

After creating the ruleset:

1. **Create a test PR** to trigger the workflow for the first time
2. Once workflow runs, `R-CMD-check` will appear in the status checks list
3. Edit ruleset if needed to add the check (if it wasn't available initially)

## 8. Troubleshooting

**"Required status check 'R-CMD-check' not found"**
- The workflow needs to run at least once before it appears
- Create a test PR or push a commit to trigger it

**Tests failing in CI but passing locally**
- Check that repository secrets are set correctly
- Verify secrets are not expired
- Check CI logs for specific error messages

**Can't merge even though tests passed**
- Make sure you've approved the PR (if approval required)
- Check that all required status checks are green
- Verify branch is up to date if that option is enabled
