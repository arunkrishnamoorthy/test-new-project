#!/bin/bash
# setup-branch-protection-curl.sh - Using cURL for reliable GitHub API calls

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

# Configuration
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_OWNER="${1:-}"
REPO_NAME="${2:-}"

# Help function
show_help() {
    echo "Usage: $0 <owner> <repo> [github_token]"
    echo ""
    echo "Examples:"
    echo "  $0 arunkrishnamoorthy my-new-repo"
    echo "  GITHUB_TOKEN=ghp_xxx $0 arunkrishnamoorthy my-new-repo"
    echo "  $0 arunkrishnamoorthy my-new-repo ghp_xxx"
    echo ""
    echo "Environment variables:"
    echo "  GITHUB_TOKEN - GitHub personal access token"
}

# Validate inputs
if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    print_error "Repository owner and name are required"
    show_help
    exit 1
fi

# Get GitHub token from parameter if provided
if [ -n "$3" ]; then
    GITHUB_TOKEN="$3"
fi

if [ -z "$GITHUB_TOKEN" ]; then
    print_error "GitHub token is required"
    echo "Set GITHUB_TOKEN environment variable or pass as third parameter"
    echo "Get token from: https://github.com/settings/tokens"
    exit 1
fi

print_status "Setting up branch protection for: $REPO_OWNER/$REPO_NAME"

# Function to create branch protection
create_branch_protection() {
    local branch="$1"
    local required_reviews="$2"
    local enforce_admins="${3:-true}"
    
    print_status "Protecting $branch branch (requires $required_reviews approvals)..."
    
    # Create the JSON payload
    local json_payload=$(cat <<EOF
{
  "required_status_checks": null,
  "enforce_admins": $enforce_admins,
  "required_pull_request_reviews": {
    "required_approving_review_count": $required_reviews,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false
}
EOF
)
    
    # Make the API call
    local response=$(curl -s -w "%{http_code}" \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "$json_payload" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/branches/$branch/protection")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        print_status "✅ $branch branch protection configured successfully"
        return 0
    else
        print_error "❌ Failed to configure $branch branch protection (HTTP $http_code)"
        echo "Response: $response_body"
        return 1
    fi
}

# Function to verify branch exists
verify_branch() {
    local branch="$1"
    
    local response=$(curl -s -w "%{http_code}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/branches/$branch")
    
    local http_code="${response: -3}"
    
    if [ "$http_code" = "200" ]; then
        return 0
    else
        print_warning "Branch '$branch' does not exist, skipping protection setup"
        return 1
    fi
}

# Function to create repository secrets
create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    
    # First, get the repository public key for encryption
    local key_response=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")
    
    local public_key=$(echo "$key_response" | grep -o '"key":"[^"]*' | sed 's/"key":"//')
    local key_id=$(echo "$key_response" | grep -o '"key_id":"[^"]*' | sed 's/"key_id":"//')
    
    if [ -z "$public_key" ] || [ -z "$key_id" ]; then
        print_error "Failed to get repository public key for secret encryption"
        return 1
    fi
    
    print_warning "⚠️  Secret encryption requires additional tooling (sodium/libsodium)"
    print_warning "For now, please set '$secret_name' manually at:"
    print_warning "https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
    
    return 0
}

# Main execution
echo "🔒 Branch Protection Setup Script"
echo "================================="
echo ""

# Verify repository exists
print_status "Verifying repository access..."
repo_response=$(curl -s -w "%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME")

repo_http_code="${repo_response: -3}"

if [ "$repo_http_code" != "200" ]; then
    print_error "Cannot access repository $REPO_OWNER/$REPO_NAME"
    print_error "Check repository name and token permissions"
    exit 1
fi

print_status "✅ Repository access verified"

# Set up branch protection
echo ""
print_status "Setting up branch protection rules..."

# Protect main branch
if verify_branch "main"; then
    create_branch_protection "main" 2 true
fi

# Protect develop branch
if verify_branch "develop"; then
    create_branch_protection "develop" 1 true
fi

# Protect staging branch
if verify_branch "staging"; then
    create_branch_protection "staging" 1 true
fi

# Configure repository settings
echo ""
print_status "Configuring repository settings..."

repo_settings_payload=$(cat <<EOF
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "delete_branch_on_merge": true,
  "allow_auto_merge": false
}
EOF
)

settings_response=$(curl -s -w "%{http_code}" \
    -X PATCH \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$repo_settings_payload" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME")

settings_http_code="${settings_response: -3}"

if [ "$settings_http_code" = "200" ]; then
    print_status "✅ Repository settings configured"
else
    print_warning "⚠️ Some repository settings may not have been configured"
fi

# Test branch protection
echo ""
print_status "Testing branch protection..."

test_protection() {
    local branch="$1"
    
    local protection_response=$(curl -s -w "%{http_code}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/branches/$branch/protection")
    
    local protection_http_code="${protection_response: -3}"
    
    if [ "$protection_http_code" = "200" ]; then
        local required_reviews=$(echo "${protection_response%???}" | grep -o '"required_approving_review_count":[0-9]*' | sed 's/"required_approving_review_count"://')
        print_status "✅ $branch branch: Protected (requires $required_reviews approvals)"
        return 0
    else
        print_warning "⚠️ $branch branch: Protection status unclear"
        return 1
    fi
}

# Test each branch
for branch in "main" "develop" "staging"; do
    if verify_branch "$branch" >/dev/null 2>&1; then
        test_protection "$branch"
    fi
done

# Summary
echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
print_status "✅ Branch protection configured for existing branches"
print_status "✅ Repository settings optimized"
print_status "✅ Ready for team development"

echo ""
print_status "🔐 Required Secrets to Add Manually:"
echo "   Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
echo ""
echo "   Add these secrets:"
echo "   • GITHUB_TOKEN - GitHub personal access token"
echo "   • OPENAI_API_KEY - OpenAI API key for AI code review"
echo "   • SNYK_TOKEN - Snyk security scanning (optional)"
echo "   • CODECOV_TOKEN - Code coverage reporting (optional)"

echo ""
print_status "🧪 Test Branch Protection:"
echo "   # This should FAIL:"
echo "   git checkout main"
echo "   echo 'test' > test.txt"
echo "   git add test.txt"
echo "   git commit -m 'test: direct commit'"
echo "   git push origin main"
echo ""
echo "   Expected: GitHub rejects the push with protection error"

echo ""
print_status "📋 Next Steps:"
echo "   1. Test branch protection with commands above"
echo "   2. Add repository secrets via web interface"
echo "   3. Create a test PR to verify GitHub Actions work"
echo "   4. Integrate this script into your CLI tool"