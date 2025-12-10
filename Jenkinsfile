pipeline {
    //
    // SECURITY & DEPENDENCY MANAGEMENT:
    //
    // We use a Docker agent to run this pipeline. This ensures:
    //
    // 1. We meet the Cortex CLI requirement for Node.js v22.
    //
    // 2. We meet the Cortex CLI requirement for GLIBC >= 2.35 (Bookworm provides 2.36).
    agent {
        docker {
            image 'node:22-bookworm'
            // We mount the Docker socket to allow "Docker-in-Docker".
            // This is required so the pipeline can run 'docker build' commands.
            args '-u root --privileged -v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    //
    // CREDENTIAL INJECTION:
    //
    // This maps the secrets stored in Jenkins Credentials to environment variables.
    //
    // Jenkins automatically masks these values in the logs.
    environment {
        //
        // CORTEX_CLOUD_API_KEY
        // maps to the secret text ID 'CORTEX_CLOUD_API_KEY' 
        CORTEX_CLOUD_API_KEY = credentials('CORTEX_CLOUD_API_KEY')
        
        //
        // CORTEX_CLOUD_API_KEY_ID
        // maps to the secret text ID 'CORTEX_CLOUD_API_KEY_ID' 
        CORTEX_CLOUD_API_KEY_ID = credentials('CORTEX_CLOUD_API_KEY_ID')
        
        //
        // CORTEX_CLOUD_API_URL
        // maps to the secret text ID 'CORTEX_CLOUD_API_URL' 
        CORTEX_CLOUD_API_URL = credentials('CORTEX_CLOUD_API_URL')

        //
        // GITHUB_REPO_URL
        // maps to the secret text ID 'GITHUB_REPO_ID'
        GITHUB_REPO_ID = credentials('GITHUB_REPO_ID')
        
        //
        // Define artifact names for consistency
        IMAGE_NAME = "jenkins_pipeline_cortex_cloud_cli"
        IMAGE_TAG = "build-${BUILD_NUMBER}"
    }

    stages {
        //
        // STAGE 1: Source Code Management
        stage('Checkout Code') {
            steps {
                script {
                    echo "--- Step 1: Cloning Repository ---"
                    // Checkout the code from the configured Git repository
                    checkout scm
                }
            }
        }

        //
        // STAGE 2: Tooling Setup
        stage('Install Cortex CLI & Prereqs') {
            steps {
                script {
                    echo "--- Step 2: Installing Dependencies ---"
                    // We must install:
                    // 1. jq (for JSON parsing)
                    // 2. curl (for downloading)
                    // 3. docker.io (for docker commands)
                    // 4. default-jre (Java 11+ is REQUIRED for cortexcli image scan) 
                    sh 'apt-get update && apt-get install -y jq curl docker.io default-jre'

                    echo "--- Step 3: Downloading Cortex CLI ---"
                    // Download logic using the authenticated API endpoint
                    sh '''
                        # 1. Request the signed download URL from Cortex Cloud
                        # Note: We specifically request the 'linux' OS and 'amd64' architecture.
                        response=$(curl -s -X GET "${CORTEX_CLOUD_API_URL}/public_api/v1/unified-cli/releases/download-link?os=linux&architecture=amd64" \
                            -H "x-xdr-auth-id: ${CORTEX_CLOUD_API_KEY_ID}" \
                            -H "Authorization: ${CORTEX_CLOUD_API_KEY}")
                    
                        # 2. Parse the JSON response to extract the URL
                        download_url=$(echo $response | jq -r ".signed_url")
                    
                        # 3. Download the binary
                        curl -o cortexcli "$download_url"
                    
                        # 4. Make the binary executable
                        chmod +x cortexcli
                    
                        # 5. Verify installation
                        ./cortexcli --version
                    '''
                }
            }
        }

        //
        // STAGE 3: Application Security (Code) Scan
        //
        // This scans IaC (Terraform), Secrets, and SCA (requirements.txt).
        stage('Cortex Code Scan') {
            steps {
                script {
                    echo "--- Step 4: Running Cortex Code Scan ---"
                    // Explanation of Flags [1, 7]:
                    // --api-base-url: The tenant URL.
                    // --directory .: Scan the current workspace directory.
                    // --repo-id: A logical name for the repo in the dashboard (Required).
                    // --branch: The branch name (Required for historical tracking).
                    // --upload-mode upload: Ensures results are sent to Cortex Cloud.
                    // --output json: Useful for parsing, though standard output is human readable.
                    // 
                    // We use '|| true' to prevent the pipeline from failing immediately if vulnerabilities are found,
                    // allowing us to proceed to the image scan. In production, you might remove this to block builds.
                    sh '''
                        ./cortexcli code scan \
                            --api-base-url "${CLOUD_API_URL}" \
                            --api-key "${CORTEX_CLOUD_API_KEY}" \
                            --api-key-id "${CORTEX_CLOUD_API_KEY_ID}" \
                            --directory . \
                            --repo-id "${GITHUB_REPO_ID}" \
                            --branch "main" \
                            --upload-mode upload \
                            --output json \
                            --output-file-path ./code_scan_results.json || true
                    '''
                }
            }
        }

        //
        // STAGE 4: Artifact Build
        stage('Build Docker Image') {
            steps {
                script {
                    echo "--- Step 5: Building Docker Image ---"
                    // Builds the image defined in the Dockerfile
                    sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                }
            }
        }

        //
        // STAGE 5: Cloud Workload Protection (Image) Scan
        //
        // This scans the built container for OS-level vulnerabilities.
        stage('Cortex Image Scan') {
            steps {
                script {
                    echo "--- Step 6: Running Cortex Image Scan ---"
                    // Explanation of Commands [8]:
                    // 'image scan': The subcommand for container analysis.
                    // The last argument is the image tag to scan.
                    
                    sh '''
                        ./cortexcli image scan \
                            --api-base-url "${CORTEX_CLOUD_API_URL}" \
                            --api-key "${CORTEX_CLOUD_API_KEY}" \
                            --api-key-id "${CORTEX_CLOUD_API_KEY_ID}" \
                            "${IMAGE_NAME}:${IMAGE_TAG}" || true
                    '''
                }
            }
        }

        //
        // STAGE 6: AWS Deployment (Commented Out)
        //
        // Included per request for future use.
        stage('Deploy to AWS (Future)') {
            steps {
                script {
                    echo "--- AWS Deployment Skipped (Uncomment to enable) ---"
                    /* // PRE-REQUISITES for this stage:
                    // 1. AWS Credentials (AWS_ACCESS_KEY_ID, etc.) added to Jenkins Credentials with ID 'aws-creds'.
                    // 2. Terraform installed in the agent container (add to apt-get install above).
                    // 3. AWS CLI installed in the agent container.

                    withCredentials([]) {
                        
                        // 1. Authenticate Docker with Amazon ECR
                        // sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com"

                        // 2. Tag the local image for ECR
                        // sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com/${IMAGE_NAME}:${IMAGE_TAG}"

                        // 3. Push the image to the registry
                        // sh "docker push <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com/${IMAGE_NAME}:${IMAGE_TAG}"

                        // 4. Update Infrastructure (Terraform)
                        // sh "terraform init"
                        // sh "terraform apply -auto-approve"

                        // 5. Force a deployment update in ECS
                        // sh "aws ecs update-service --cluster production-cluster --service my-app --force-new-deployment"
                    }
                    */
                }
            }
        }
    }

    //
    // Post-build actions to clean up and archive reports
    post {
        always {
            script {
                try {
                    // Try to archive and clean up
                    archiveArtifacts artifacts: '*.json', allowEmptyArchive: true
                    cleanWs()
                } catch (Exception e) {
                    // This handles cases where the Docker agent died early (like missing credentials)
                    echo "Warning: Could not archive artifacts or clean workspace. The agent may have failed to start. (Error: ${e.message})"
                }
            }
        }
    }
} // End of pipeline