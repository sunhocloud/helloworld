#!/bin/bash
set -e

echo "🔨 Building Helm chart dependencies..."

# Base charts
echo "📦 Building Airflow base dependencies..."
cd management-base/airflow
helm dependency build

echo "📦 Building PostgreSQL dependencies..."
cd ../../statefulset-base/postgresql
helm dependency build

echo "📦 Building Redis dependencies..."
cd ../redis
helm dependency build

# Test infrastructure
echo "📦 Building test-infrastructure dependencies..."
cd ../../test-infrastructure
helm dependency build

# Customer service (optional)
echo "📦 Building customer-service dependencies..."
cd ../services/customer-service
helm dependency build

echo "✅ All Helm chart dependencies built successfully!"
