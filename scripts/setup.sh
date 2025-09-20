#!/bin/bash
# simple-branch-protection.sh - Working version using step-by-step approach

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get repository info
REPO_OWNER=$(gh repo view --json owner --jq .owner.login)
REPO_NAME=$(gh repo view --json name --jq .name)

echo "🔒 Setting up branch protection for: $REPO_OWNER/$REPO_NAME"
echo ""

# Method 1: Try simple approach first
echo "🔧 Method 1: Basic Protection (Recommended)"
echo "This will set up basic branch protection that definitely works."
echo ""

setup_basic_protection() {
    local branch=$1
    local required_reviews=$2
    
    print_status "Setting up basic protection for $branch branch (requires $required_reviews reviews)..."
    
    # Create a minimal protection rule that works
    gh api repos/"$REPO_OWNER"/"$REPO_NAME"/branches/"$branch"/protection \
        --method PUT \
        --raw-field required_status_checks=null \
        --raw-field enforce_admins=true \
        --raw-field required_pull_request_reviews="{\"required_approving_review_count\":$required_reviews,\"dismiss_stale_reviews\":true}" \
        --raw-field restrictions=null \
        --raw-field allow_force_pushes=false \
        --raw-field allow_deletions=false
    
    if [ $? -eq 0 ]; then
        print_status "✅ $branch branch protection configured successfully"
        return 0
    else
        print_error "❌ Failed to configure $branch branch protection"
        return 1
    fi
}

# Try setting up protection for each branch
echo "Setting up branch protection..."

if setup_basic_protection "main" 2; then
    echo "✅ Main branch: Protected (requires 2 approvals)"
else
    echo "❌ Main branch: Failed to protect"
fi

if setup_basic_protection "develop" 1; then
    echo "✅ Develop branch: Protected (requires 1 approval)"
else
    echo "❌ Develop branch: Failed to protect"
fi

if setup_basic_protection "staging" 1; then
    echo "✅ Staging branch: Protected (requires 1 approval)"
else
    echo "❌ Staging branch: Failed to protect"
fi

echo ""
echo "🧪 Testing branch protection..."

# Test if protection is working
test_protection() {
    local branch=$1
    print_status "Testing protection on $branch branch..."
    
    local protection_status=$(gh api repos/"$REPO_OWNER"/"$REPO_NAME"/branches/"$branch"/protection --jq '.required_pull_request_reviews.required_approving_review_count' 2>/dev/null || echo "failed")
    
    if [ "$protection_status" != "failed" ]; then
        echo "  ✅ $branch branch is protected (requires $protection_status approvals)"
        return 0
    else
        echo "  ❌ $branch branch protection failed"
        return 1
    fi
}

test_protection "main"
test_protection "develop"
test_protection "staging"

echo ""
echo "🔧 Alternative Method: Manual Setup via Web Interface"
echo ""
echo "If the script method didn't work, you can set up protection manually:"
echo "1. Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/branches"
echo "2. Click 'Add rule'"
echo "3. For each branch (main, develop, staging):"
echo "   - Branch name pattern: [branch-name]"
echo "   - ✅ Require a pull request before merging"
echo "   - ✅ Require approvals: 2 (for main), 1 (for develop/staging)"
echo "   - ✅ Dismiss stale PR approvals when new commits are pushed"
echo "   - ✅ Include administrators"
echo "   - ✅ Restrict pushes that create files"
echo "   - Click 'Create'"

echo ""
echo "🧪 IMMEDIATE TEST - Run this now:"
echo ""
echo "# This should FAIL if protection is working:"
echo "git checkout main"
echo "echo 'test protection' > test.txt"
echo "git add test.txt"
echo "git commit -m 'test: should be blocked'"
echo "git push origin main"
echo ""
echo "Expected result: GitHub should reject the push with an error about requiring PR reviews."

echo ""
echo "📋 What to do next:"
echo "1. ✅ Test the protection with the commands above"
echo "2. ✅ If protection works: continue with setting up secrets"
echo "3. ✅ If protection doesn't work: use the manual web interface method"
echo "4. ✅ Add repository secrets for CI/CD workflows"

echo ""
echo "🔐 Repository Secrets to Add:"
echo "   Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
echo "   Add:"
echo "   • GITHUB_TOKEN - Your GitHub personal access token"
echo "   • OPENAI_API_KEY - OpenAI API key for AI code review"