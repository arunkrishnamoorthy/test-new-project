#!/bin/bash
# complete-repo-setup.sh - Branch protection + automated secrets creation

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

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Configuration
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_OWNER="${1:-}"
REPO_NAME="${2:-}"
SETUP_SECRETS="${3:-true}"

# Validate inputs
if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    print_error "Repository owner and name are required"
    echo "Usage: $0 <owner> <repo> [setup_secrets] [github_token]"
    echo ""
    echo "Examples:"
    echo "  $0 arunkrishnamoorthy my-repo true"
    echo "  $0 arunkrishnamoorthy my-repo false ghp_token"
    echo "  GITHUB_TOKEN=ghp_xxx $0 arunkrishnamoorthy my-repo"
    exit 1
fi

if [ -n "$4" ]; then
    GITHUB_TOKEN="$4"
fi

if [ -z "$GITHUB_TOKEN" ]; then
    print_error "GitHub token is required"
    echo "Set GITHUB_TOKEN environment variable or pass as fourth parameter"
    exit 1
fi

echo "🚀 Complete Repository Setup"
echo "============================"
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Setup Secrets: $SETUP_SECRETS"
echo ""

# ========================================
# PART 1: BRANCH PROTECTION SETUP
# ========================================

setup_branch_protection() {
    print_header "Setting Up Branch Protection"

    # Verify repository access
    print_status "Verifying repository access..."
    repo_response=$(curl -s -w "%{http_code}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME")

    repo_http_code="${repo_response: -3}"

    if [ "$repo_http_code" != "200" ]; then
        print_error "Cannot access repository $REPO_OWNER/$REPO_NAME"
        return 1
    fi

    print_status "✅ Repository access verified"

    # Function to create branch protection
    create_branch_protection() {
        local branch="$1"
        local required_reviews="$2"
        
        print_status "Protecting $branch branch (requires $required_reviews approvals)..."
        
        local json_payload=$(cat <<EOF
{
  "required_status_checks": null,
  "enforce_admins": true,
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
        
        local response=$(curl -s -w "%{http_code}" \
            -X PUT \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -d "$json_payload" \
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/branches/$branch/protection")
        
        local http_code="${response: -3}"
        
        if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
            print_status "✅ $branch branch protection configured successfully"
            return 0
        else
            print_warning "⚠️ Could not configure $branch branch protection (branch may not exist)"
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
            return 1
        fi
    }

    # Set up protection for each branch
    local protected_branches=0
    
    if verify_branch "main"; then
        if create_branch_protection "main" 2; then
            ((protected_branches++))
        fi
    fi

    if verify_branch "develop"; then
        if create_branch_protection "develop" 1; then
            ((protected_branches++))
        fi
    fi

    if verify_branch "staging"; then
        if create_branch_protection "staging" 1; then
            ((protected_branches++))
        fi
    fi

    # Configure repository settings
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

    curl -s -w "%{http_code}" \
        -X PATCH \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "$repo_settings_payload" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME" > /dev/null

    print_status "✅ Repository settings configured"
    print_status "✅ Protected $protected_branches branches successfully"
    
    return 0
}

# ========================================
# PART 2: SECRETS SETUP
# ========================================

setup_repository_secrets() {
    print_header "Setting Up Repository Secrets"

    # Function to check if Python encryption is available
    check_encryption_capability() {
        if command -v python3 &> /dev/null; then
            if python3 -c "import nacl" 2>/dev/null; then
                return 0
            fi
        fi
        return 1
    }

    # Function to encrypt secret (simplified version)
    encrypt_secret_simple() {
        local secret_value="$1"
        local public_key="$2"
        
        if check_encryption_capability; then
            python3 << EOF
import base64
from nacl import encoding, public

def encrypt_secret(secret_value, public_key):
    public_key_bytes = base64.b64decode(public_key)
    public_key_obj = public.PublicKey(public_key_bytes)
    sealed_box = public.SealedBox(public_key_obj)
    encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
    return base64.b64encode(encrypted).decode("utf-8")

print(encrypt_secret("$secret_value", "$public_key"))
EOF
        else
            # Return a placeholder that will clearly indicate it needs to be replaced
            echo "NEEDS_REAL_VALUE_$(echo "$secret_value" | head -c 20 | base64)"
        fi
    }

    # Get repository public key
    print_status "Getting repository public key for encryption..."
    
    local key_response=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")
    
    local public_key=$(echo "$key_response" | grep -o '"key":"[^"]*' | sed 's/"key":"//')
    local key_id=$(echo "$key_response" | grep -o '"key_id":"[^"]*' | sed 's/"key_id":"//')
    
    if [ -z "$public_key" ] || [ -z "$key_id" ]; then
        print_error "Failed to get repository public key"
        print_warning "Secrets must be set manually at: https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
        return 1
    fi

    print_status "Repository public key obtained successfully"

    # Function to create a secret
    create_secret() {
        local secret_name="$1"
        local secret_value="$2"
        
        print_status "Creating secret: $secret_name"
        
        local encrypted_value=$(encrypt_secret_simple "$secret_value" "$public_key")
        
        if [ $? -eq 0 ] && [ -n "$encrypted_value" ]; then
            local response=$(curl -s -w "%{http_code}" \
                -X PUT \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer $GITHUB_TOKEN" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                -d "{\"encrypted_value\":\"$encrypted_value\",\"key_id\":\"$key_id\"}" \
                "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/$secret_name")
            
            local http_code="${response: -3}"
            
            if [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
                print_status "✅ Secret '$secret_name' created successfully"
                return 0
            else
                print_warning "⚠️ Failed to create secret '$secret_name'"
                return 1
            fi
        else
            print_warning "⚠️ Could not encrypt secret '$secret_name'"
            return 1
        fi
    }

    # Define dummy secrets
    declare -A secrets=(
        ["GITHUB_TOKEN"]="ghp_REPLACE_WITH_YOUR_GITHUB_TOKEN_12345678901234567890"
        ["OPENAI_API_KEY"]="sk-REPLACE_WITH_YOUR_OPENAI_API_KEY_1234567890abcdef"
        ["AARINI_API_KEY"]="aarini_REPLACE_WITH_YOUR_AARINI_API_KEY_1234567890"
        ["SNYK_TOKEN"]="snyk_REPLACE_WITH_YOUR_SNYK_TOKEN_1234567890abcdef"
        ["CODECOV_TOKEN"]="codecov_REPLACE_WITH_YOUR_CODECOV_TOKEN_1234567890"
        ["SEMGREP_APP_TOKEN"]="semgrep_REPLACE_WITH_YOUR_SEMGREP_TOKEN_1234567890"
        ["SLACK_WEBHOOK"]="https://hooks.slack.com/services/REPLACE/WITH/YOUR/WEBHOOK"
    )

    local created_count=0
    local total_count=${#secrets[@]}

    # Check encryption capability
    if ! check_encryption_capability; then
        print_warning "⚠️ PyNaCl not available. Installing..."
        print_status "Installing PyNaCl for secret encryption..."
        
        if command -v pip3 &> /dev/null; then
            pip3 install pynacl --quiet 2>/dev/null || {
                print_warning "Could not install PyNaCl. Secrets will need manual setup."
            }
        else
            print_warning "pip3 not available. Secrets will need manual setup."
        fi
    fi

    # Create each secret
    for secret_name in "${!secrets[@]}"; do
        local secret_value="${secrets[$secret_name]}"
        
        if create_secret "$secret_name" "$secret_value"; then
            ((created_count++))
        fi
    done

    # Summary
    print_status "Secrets creation summary: $created_count/$total_count created"

    if [ $created_count -gt 0 ]; then
        echo ""
        print_status "🔐 Secrets created with dummy values. Update them with real values:"
        echo "   Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
        echo ""
        print_warning "⚠️ IMPORTANT: These are dummy values! Replace with real API keys before using workflows."
        echo ""
        echo "Required secrets to update:"
        for secret_name in "${!secrets[@]}"; do
            echo "   • $secret_name"
        done
    else
        print_warning "No secrets were created automatically."
        print_status "Please set secrets manually at: https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
    fi
    
    return 0
}

# ========================================
# MAIN EXECUTION
# ========================================

main() {
    # Step 1: Branch Protection
    if setup_branch_protection; then
        print_status "✅ Branch protection setup completed"
    else
        print_error "❌ Branch protection setup failed"
        exit 1
    fi

    echo ""

    # Step 2: Secrets (if requested)
    if [ "$SETUP_SECRETS" = "true" ]; then
        if setup_repository_secrets; then
            print_status "✅ Secrets setup completed"
        else
            print_warning "⚠️ Secrets setup had issues"
        fi
    else
        print_status "⏭️ Skipping secrets setup (as requested)"
    fi

    # Final summary
    print_header "Setup Complete!"
    echo ""
    print_status "✅ Repository $REPO_OWNER/$REPO_NAME is configured for team development"
    echo ""
    
    if [ "$SETUP_SECRETS" = "true" ]; then
        print_status "📋 Next Steps:"
        echo "   1. Update repository secrets with real API keys"
        echo "   2. Test branch protection with a direct push (should be blocked)"
        echo "   3. Create a test PR to verify GitHub Actions work"
        echo "   4. Share repository with your team"
    else
        print_status "📋 Next Steps:"
        echo "   1. Set up repository secrets manually if needed"
        echo "   2. Test branch protection with a direct push (should be blocked)"
        echo "   3. Create a test PR to verify the workflow"
    fi

    echo ""
    print_status "🧪 Test Branch Protection:"
    echo "   # This should FAIL:"
    echo "   git checkout main"
    echo "   echo 'test' > test.txt"
    echo "   git add test.txt && git commit -m 'test: direct commit'"
    echo "   git push origin main"
    echo ""
    echo "   Expected: GitHub rejects the push with protection error"
}

# Run main function
main