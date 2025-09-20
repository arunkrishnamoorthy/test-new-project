#!/usr/bin/env node
// setup-branch-protection.js - Node.js script for branch protection setup

const { Octokit } = require('@octokit/rest');
const chalk = require('chalk');

class BranchProtectionSetup {
  constructor(token) {
    this.octokit = new Octokit({
      auth: token,
      userAgent: 'branch-protection-setup/1.0.0'
    });
  }

  log(message, type = 'info') {
    const icons = {
      info: '🔍',
      success: '✅',
      error: '❌',
      warning: '⚠️'
    };
    
    const colors = {
      info: chalk.blue,
      success: chalk.green,
      error: chalk.red,
      warning: chalk.yellow
    };
    
    console.log(`${icons[type]} ${colors[type](message)}`);
  }

  async verifyRepository(owner, repo) {
    try {
      await this.octokit.rest.repos.get({ owner, repo });
      this.log(`Repository ${owner}/${repo} accessed successfully`, 'success');
      return true;
    } catch (error) {
      this.log(`Cannot access repository ${owner}/${repo}: ${error.message}`, 'error');
      return false;
    }
  }

  async verifyBranch(owner, repo, branch) {
    try {
      await this.octokit.rest.repos.getBranch({ owner, repo, branch });
      return true;
    } catch (error) {
      this.log(`Branch '${branch}' does not exist, skipping`, 'warning');
      return false;
    }
  }

  async createBranchProtection(owner, repo, branch, requiredReviews = 1, enforceAdmins = true) {
    try {
      this.log(`Setting up protection for '${branch}' branch (${requiredReviews} required reviews)...`);
      
      const protectionConfig = {
        owner,
        repo,
        branch,
        required_status_checks: null,
        enforce_admins: enforceAdmins,
        required_pull_request_reviews: {
          required_approving_review_count: requiredReviews,
          dismiss_stale_reviews: true,
          require_code_owner_reviews: false,
          require_last_push_approval: false
        },
        restrictions: null,
        allow_force_pushes: false,
        allow_deletions: false,
        block_creations: false,
        required_conversation_resolution: false
      };

      await this.octokit.rest.repos.updateBranchProtection(protectionConfig);
      this.log(`${branch} branch protection configured successfully`, 'success');
      return true;
    } catch (error) {
      this.log(`Failed to configure ${branch} branch protection: ${error.message}`, 'error');
      return false;
    }
  }

  async configureRepositorySettings(owner, repo) {
    try {
      this.log('Configuring repository settings...');
      
      await this.octokit.rest.repos.update({
        owner,
        repo,
        allow_squash_merge: true,
        allow_merge_commit: false,
        allow_rebase_merge: false,
        delete_branch_on_merge: true,
        allow_auto_merge: false
      });
      
      this.log('Repository settings configured successfully', 'success');
      return true;
    } catch (error) {
      this.log(`Failed to configure repository settings: ${error.message}`, 'warning');
      return false;
    }
  }

  async enableSecurityFeatures(owner, repo) {
    try {
      this.log('Enabling security features...');
      
      // Enable vulnerability alerts
      try {
        await this.octokit.rest.repos.enableVulnerabilityAlerts({ owner, repo });
        this.log('Vulnerability alerts enabled', 'success');
      } catch (error) {
        this.log('Could not enable vulnerability alerts', 'warning');
      }

      // Enable automated security fixes
      try {
        await this.octokit.rest.repos.enableAutomatedSecurityFixes({ owner, repo });
        this.log('Automated security fixes enabled', 'success');
      } catch (error) {
        this.log('Could not enable automated security fixes', 'warning');
      }

      return true;
    } catch (error) {
      this.log(`Security features setup had issues: ${error.message}`, 'warning');
      return false;
    }
  }

  async testBranchProtection(owner, repo, branch) {
    try {
      const { data } = await this.octokit.rest.repos.getBranchProtection({ owner, repo, branch });
      const requiredReviews = data.required_pull_request_reviews?.required_approving_review_count || 0;
      this.log(`${branch} branch: Protected (requires ${requiredReviews} approvals)`, 'success');
      return true;
    } catch (error) {
      this.log(`${branch} branch: Protection verification failed`, 'warning');
      return false;
    }
  }

  async createSecret(owner, repo, secretName, secretValue) {
    try {
      // Get repository public key for encryption
      const { data: publicKeyData } = await this.octokit.rest.actions.getRepoPublicKey({ owner, repo });
      
      // Note: This requires sodium library for encryption
      // For now, we'll just log instructions for manual setup
      this.log(`Secret '${secretName}' needs to be set manually`, 'warning');
      this.log(`Go to: https://github.com/${owner}/${repo}/settings/secrets/actions`, 'info');
      
      return false; // Return false to indicate manual setup needed
    } catch (error) {
      this.log(`Failed to setup secret ${secretName}: ${error.message}`, 'error');
      return false;
    }
  }

  async setupRepository(owner, repo, config = {}) {
    const {
      branches = { main: 2, develop: 1, staging: 1 },
      enforceAdmins = true,
      enableSecurity = true,
      secrets = {}
    } = config;

    console.log(chalk.blue.bold('🔒 Branch Protection Setup'));
    console.log(chalk.blue.bold('=========================='));
    console.log('');

    // Verify repository access
    if (!(await this.verifyRepository(owner, repo))) {
      process.exit(1);
    }

    console.log('');
    this.log('Setting up branch protection rules...');

    // Set up branch protection for each branch
    const results = {};
    for (const [branch, requiredReviews] of Object.entries(branches)) {
      if (await this.verifyBranch(owner, repo, branch)) {
        results[branch] = await this.createBranchProtection(owner, repo, branch, requiredReviews, enforceAdmins);
      } else {
        results[branch] = false;
      }
    }

    // Configure repository settings
    console.log('');
    await this.configureRepositorySettings(owner, repo);

    // Enable security features
    if (enableSecurity) {
      console.log('');
      await this.enableSecurityFeatures(owner, repo);
    }

    // Test branch protection
    console.log('');
    this.log('Testing branch protection...');
    for (const branch of Object.keys(branches)) {
      if (results[branch]) {
        await this.testBranchProtection(owner, repo, branch);
      }
    }

    // Setup secrets (manual for now)
    if (Object.keys(secrets).length > 0) {
      console.log('');
      this.log('Setting up repository secrets...');
      for (const [secretName, secretValue] of Object.entries(secrets)) {
        await this.createSecret(owner, repo, secretName, secretValue);
      }
    }

    // Summary
    console.log('');
    console.log(chalk.green.bold('🎉 Setup Complete!'));
    console.log(chalk.green.bold('=================='));
    console.log('');

    const successfulBranches = Object.entries(results).filter(([, success]) => success);
    this.log(`Branch protection configured for: ${successfulBranches.map(([branch]) => branch).join(', ')}`, 'success');
    this.log('Repository settings optimized', 'success');
    this.log('Ready for team development', 'success');

    console.log('');
    this.log('🔐 Manual Setup Required:', 'warning');
    console.log(`   Go to: https://github.com/${owner}/${repo}/settings/secrets/actions`);
    console.log('   Add these secrets:');
    console.log('   • GITHUB_TOKEN - GitHub personal access token');
    console.log('   • OPENAI_API_KEY - OpenAI API key for AI code review');
    console.log('   • SNYK_TOKEN - Snyk security scanning (optional)');

    console.log('');
    this.log('🧪 Test Branch Protection:', 'info');
    console.log('   # This should FAIL:');
    console.log('   git checkout main');
    console.log('   echo "test" > test.txt');
    console.log('   git add test.txt');
    console.log('   git commit -m "test: direct commit"');
    console.log('   git push origin main');
    console.log('');
    console.log('   Expected: GitHub rejects the push with protection error');

    return {
      success: successfulBranches.length > 0,
      results,
      repository: `${owner}/${repo}`
    };
  }
}

// CLI usage
async function main() {
  const args = process.argv.slice(2);
  
  if (args.length < 2 || args.includes('--help') || args.includes('-h')) {
    console.log('Usage: node setup-branch-protection.js <owner> <repo> [token]');
    console.log('');
    console.log('Examples:');
    console.log('  node setup-branch-protection.js arunkrishnamoorthy my-repo');
    console.log('  GITHUB_TOKEN=ghp_xxx node setup-branch-protection.js arunkrishnamoorthy my-repo');
    console.log('  node setup-branch-protection.js arunkrishnamoorthy my-repo ghp_xxx');
    console.log('');
    console.log('Environment variables:');
    console.log('  GITHUB_TOKEN - GitHub personal access token');
    console.log('');
    console.log('Configuration:');
    console.log('  Edit the config object in the script to customize branch protection rules');
    process.exit(0);
  }

  const [owner, repo, tokenArg] = args;
  const token = tokenArg || process.env.GITHUB_TOKEN;

  if (!token) {
    console.error(chalk.red('❌ GitHub token is required'));
    console.error('Set GITHUB_TOKEN environment variable or pass as third argument');
    console.error('Get token from: https://github.com/settings/tokens');
    process.exit(1);
  }

  try {
    const setup = new BranchProtectionSetup(token);
    
    // Configuration for branch protection
    const config = {
      branches: {
        main: 2,     // 2 required reviews
        develop: 1,  // 1 required review
        staging: 1   // 1 required review
      },
      enforceAdmins: true,
      enableSecurity: true,
      secrets: {
        // Add secrets here if you want to set them programmatically
        // Note: Requires additional encryption setup
      }
    };

    const result = await setup.setupRepository(owner, repo, config);
    
    if (result.success) {
      console.log(chalk.green('\n✅ Branch protection setup completed successfully!'));
      process.exit(0);
    } else {
      console.log(chalk.yellow('\n⚠️ Branch protection setup completed with some issues'));
      process.exit(1);
    }
  } catch (error) {
    console.error(chalk.red(`\n❌ Setup failed: ${error.message}`));
    process.exit(1);
  }
}

// Export for use as module
module.exports = BranchProtectionSetup;

// Run as CLI if called directly
if (require.main === module) {
  main().catch(error => {
    console.error(chalk.red(`Fatal error: ${error.message}`));
    process.exit(1);
  });
}