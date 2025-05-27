#! groovy
pipeline {
  agent any

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Install Dependencies') {
      steps {
        sh 'npm config set registry http://registry.npmjs.org/'
        sh 'npm install'
      }
    }

    stage('Test') {
      steps {
        sh 'npx mocha'
      }
    }

    stage('Cleanup') {
      steps {
        echo 'Cleaning up node_modules'
        sh 'rm -rf node_modules'
      }
    }
  }
}
