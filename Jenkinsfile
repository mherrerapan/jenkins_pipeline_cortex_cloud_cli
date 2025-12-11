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
        IMAGE_NAME = 'my-app'
        IMAGE_TAG  = "${BUILD_NUMBER}"
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
                    sh 'apt-get update && apt-get install -y jq curl docker.io default-jre binutils'

                    echo "--- Step 3: Downloading Cortex CLI ---"
                    // Download logic using the authenticated API endpoint
                    sh '''
                        set -e # Fail script immediately if any command fails

                        # 2. Manually install libhyperscan5 (Required for Image Scan)
                        # This library was removed in Debian 12 (Bookworm) but is required by Cortex.
                        # We download the Debian 11 (Bullseye) version which works.
                        curl -f -L -o libhyperscan5.deb http://ftp.us.debian.org/debian/pool/main/h/hyperscan/libhyperscan5_5.4.0-2_amd64.deb
                        apt-get install -y ./libhyperscan5.deb

                        # 3. Download Cortex CLI
                        # Request the signed download URL from Cortex Cloud
                        response=$(curl -s -X GET "${CORTEX_CLOUD_API_URL}/public_api/v1/unified-cli/releases/download-link?os=linux&architecture=amd64" \
                            -H "x-xdr-auth-id: ${CORTEX_CLOUD_API_KEY_ID}" \
                            -H "Authorization: ${CORTEX_CLOUD_API_KEY}")
                    
                        # Parse the JSON response
                        download_url=$(echo $response | jq -r ".signed_url")
                    
                        # Download and Install
                        curl -o cortexcli "$download_url"
                        chmod +x ./cortexcli
                        
                        # Verify
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
            // -----------------------------------------------------------
            // SKIP INSTRUCTION:
            // The 'when' block below forces Jenkins to skip this stage.
            // To re-enable the scan later, change return to true:
            when {
                expression { return false }
            }
            // -----------------------------------------------------------

            steps {
                script {
                    echo "--- Step 4: Running Cortex Code Scan ---"
                    // 1. Create ignore file dynamically to exclude Jenkinsfile
                    sh 'echo "Jenkinsfile" > .cortexignore'
                    // Explanation of Flags [1, 7]:
                    // --api-base-url: The tenant URL.
                    // --directory .: Scan the current workspace directory.
                    // --repo-id: A logical name for the repo in the dashboard (Required).
                    // --branch: The branch name (Required for historical tracking).
                    // --upload-mode upload: Ensures results are sent to Cortex Cloud.
                    // --output json: Useful for parsing, though standard output is human readable.
                    // --output options --> (e.g., json, sarif, junitxml, spdx, cli, cyclonedx, cyclonedx_json).
                    // We use '|| true' to prevent the pipeline from failing immediately if vulnerabilities are found,
                    // allowing us to proceed to the image scan. In production, you might remove this to block builds.
                    
                    sh '''
                        # 1. Enable Shell Verbosity (Prints every command being run)
                        set -x

                        # 2. RUN COMMAND
                        # "2>&1" -> Merges errors into standard output so you see them.

                        CLEAN_URL=$(echo "${CORTEX_CLOUD_API_URL}" | tr -d '\n\r')
                        CLEAN_KEY=$(echo "${CORTEX_CLOUD_API_KEY}" | tr -d '\n\r')
                        CLEAN_KEY_ID=$(echo "${CORTEX_CLOUD_API_KEY_ID}" | tr -d '\n\r')
                        CLEAN_REPO_ID=$(echo "${GITHUB_REPO_ID}" | tr -d '\n\r')

                        # 2. RUN COMMAND (With Auth Flags First)
                        ./cortexcli \
                            --api-base-url "$CLEAN_URL" \
                            --api-key "$CLEAN_KEY" \
                            --api-key-id "$CLEAN_KEY_ID" \
                            --log-level debug \
                            code scan \
                            --directory . \
                            --repo-id "$CLEAN_REPO_ID" \
                            --branch "main" \
                            --upload-mode upload \
                            --output cli \
                            --source "JENKINS" 2>&1 #|| true
                            #--output-file-path ./code_scan_results.json 2>&1 
                    '''
                }
            }
        }

        //
        // STAGE 4: Artifact Build
        stage('Build Docker Image') {
            // -----------------------------------------------------------
            // SKIP INSTRUCTION:
            // The 'when' block below forces Jenkins to skip this stage.
            // To re-enable the scan later, change return to true:
            when {
                expression { return true }
            }
            // -----------------------------------------------------------
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
            // -----------------------------------------------------------
            // SKIP INSTRUCTION:
            // The 'when' block below forces Jenkins to skip this stage.
            // To re-enable the scan later, change return to true:
            when {
                expression { return true }
            }
            // -----------------------------------------------------------
            steps {
                script {
                    echo "--- Step 6: Running Cortex Image Scan ---"
                    // Explanation of Commands [8]:
                    // 'image scan': The subcommand for container analysis.
                    // The last argument is the image tag to scan.
                    // --output options --> (human-readable, json (default: human-readable)).
                    // "2>&1" -> Merges errors into standard output so you see them.
                    
                    sh '''
                        set -x
                        
                        # 1. Setup Variables
                        CLEAN_URL=$(echo "${CORTEX_CLOUD_API_URL}" | tr -d '\n\r')
                        CLEAN_KEY=$(echo "${CORTEX_CLOUD_API_KEY}" | tr -d '\n\r')
                        CLEAN_KEY_ID=$(echo "${CORTEX_CLOUD_API_KEY_ID}" | tr -d '\n\r')

                        # 2. Prerequisites
                        java -version

                        # 5. RUN SCAN (Absolute Path Method)
                        ./cortexcli \
                            --api-base-url "$CLEAN_URL" \
                            --api-key "$CLEAN_KEY" \
                            --api-key-id "$CLEAN_KEY_ID" \
                            --log-level debug \
                            --timeout 300 \
                            image scan "${IMAGE_NAME}:${IMAGE_TAG}" 2>&1
                    '''
                }
            }
        }

        //
        // STAGE 6: Generate SBOM
        //
        // This generates a Software Bill of Materials (SBOM) for the image 
        // we just built and saves it as a JSON file.
        stage('Generate SBOM') {
            // -----------------------------------------------------------
            // SKIP INSTRUCTION:
            // The 'when' block below forces Jenkins to skip this stage.
            // To re-enable the scan later, change return to true:
            when {
                expression { return true }
            }
            // -----------------------------------------------------------
            steps {
                script {
                    echo "--- Step 7: Generating SBOM ---"
                    
                    sh '''
                        # 1. Enable Shell Verbosity (Prints every command being run)
                        set -x

                        # 2. RUN COMMAND
                        # "2>&1" -> Merges errors into standard output so you see them.

                        CLEAN_URL=$(echo "${CORTEX_CLOUD_API_URL}" | tr -d '\n\r')
                        CLEAN_KEY=$(echo "${CORTEX_CLOUD_API_KEY}" | tr -d '\n\r')
                        CLEAN_KEY_ID=$(echo "${CORTEX_CLOUD_API_KEY_ID}" | tr -d '\n\r')

                        # Generate SBOM
                        # We output to a JSON file so the 'post' step can archive it.
                        
                        ./cortexcli \
                            --api-base-url "$CLEAN_URL" \
                            --api-key "$CLEAN_KEY" \
                            --api-key-id "$CLEAN_KEY_ID" \
                            --log-level debug \
                            --timeout 300 \
                            image sbom "${IMAGE_NAME}:${IMAGE_TAG}" 2>&1 \
                            --output-format json \
                            --output-file "sbom-${BUILD_NUMBER}.json" #|| true 
                            
                    '''
                }
            }
        }

        //
        // STAGE 7: AWS Deployment (Commented Out)
        //
        // Included per request for future use.
        stage('Deploy to AWS (Future)') {
            // -----------------------------------------------------------
            // SKIP INSTRUCTION:
            // The 'when' block below forces Jenkins to skip this stage.
            // To re-enable the scan later, change return to true:
            when {
                expression { return true }
            }
            // -----------------------------------------------------------
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