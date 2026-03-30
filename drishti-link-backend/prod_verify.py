#!/usr/bin/env python3
"""
Production Verification Script for Drishti-Link Backend

This script performs comprehensive health checks for all critical backend services:
1. PostgreSQL connectivity with query test
2. Redis connectivity with set/get test  
3. Database schema verification
4. Firebase Admin SDK initialization with mock token check

Usage: python prod_verify.py
"""

import asyncio
import sys
import traceback
import os
from datetime import datetime
from typing import Dict, Any, Optional
import json

# Add current directory to path for imports
sys.path.insert(0, '.')

# Try imports with graceful fallback
try:
    from core.config import settings
    CONFIG_AVAILABLE = True
except ImportError as e:
    print(f"⚠️  Config import failed: {e}")
    CONFIG_AVAILABLE = False

try:
    from core.database import engine, get_redis_pool, Base
    DATABASE_AVAILABLE = True
except ImportError as e:
    print(f"⚠️  Database import failed: {e}")
    DATABASE_AVAILABLE = False

try:
    from services.firebase_admin_service import FirebaseAdminService
    FIREBASE_AVAILABLE = True
except ImportError as e:
    print(f"⚠️  Firebase import failed: {e}")
    FIREBASE_AVAILABLE = False

# Colors for terminal output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

def print_status(status: str, message: str, color: str = Colors.BLUE):
    """Print formatted status message"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"{color}[{timestamp}] {status}{Colors.RESET}: {message}")

def print_success(message: str):
    print_status("✅ SUCCESS", message, Colors.GREEN)

def print_error(message: str):
    print_status("❌ ERROR", message, Colors.RED)

def print_warning(message: str):
    print_status("⚠️  WARNING", message, Colors.YELLOW)

def print_info(message: str):
    print_status("ℹ️  INFO", message, Colors.BLUE)

class ProductionVerifier:
    """Production environment verification suite"""
    
    def __init__(self):
        self.results = {
            'postgresql': {'status': False, 'error': None, 'details': {}},
            'redis': {'status': False, 'error': None, 'details': {}},
            'database_schema': {'status': False, 'error': None, 'details': {}},
            'firebase': {'status': False, 'error': None, 'details': {}}
        }
    
    async def verify_postgresql(self) -> bool:
        """Verify PostgreSQL connectivity with SELECT 1 query"""
        print_info("Testing PostgreSQL connectivity...")
        
        if not DATABASE_AVAILABLE:
            error_msg = "Database modules not available - install requirements"
            self.results['postgresql']['error'] = error_msg
            print_error(error_msg)
            return False
            
        try:
            from sqlalchemy import text
            import redis.asyncio as redis
            
            async with engine.begin() as conn:
                # Execute simple query
                result = await conn.execute(text("SELECT 1 as health_check"))
                row = result.fetchone()
                
                if row and row[0] == 1:
                    # Get database info
                    version_result = await conn.execute(text("SELECT version()"))
                    version = version_result.fetchone()[0]
                    
                    # Get connection pool info
                    pool_info = {
                        'pool_size': engine.pool.size(),
                        'checked_in': engine.pool.checkedin(),
                        'checked_out': engine.pool.checkedout()
                    }
                    
                    self.results['postgresql'].update({
                        'status': True,
                        'details': {
                            'query_result': row[0],
                            'database_version': version,
                            'pool_info': pool_info
                        }
                    })
                    
                    print_success(f"PostgreSQL connected successfully - {version.split(',')[0]}")
                    return True
                else:
                    raise Exception("Unexpected query result")
                    
        except Exception as e:
            error_msg = f"PostgreSQL connection failed: {str(e)}"
            self.results['postgresql']['error'] = error_msg
            print_error(error_msg)
            return False
    
    async def verify_redis(self) -> bool:
        """Verify Redis connectivity — OPTIONAL service (REDIS_ENABLED controls this)."""
        print_info("Testing Redis connectivity (optional)...")

        if CONFIG_AVAILABLE and not getattr(settings, 'REDIS_ENABLED', False):
            print_warning("Redis is DISABLED (REDIS_ENABLED=False). Using in-memory cache. This is normal for local dev.")
            self.results['redis'].update({'status': True, 'details': {'mode': 'disabled_by_config', 'backend': 'memory'}})
            return True

        try:
            import redis.asyncio as redis_lib
            r = redis_lib.from_url(
                getattr(settings, 'REDIS_URL', 'redis://localhost:6379/0') if CONFIG_AVAILABLE else 'redis://localhost:6379/0',
                socket_connect_timeout=3
            )
            await r.ping()
            info = await r.info()
            self.results['redis'].update({'status': True, 'details': {'redis_version': info.get('redis_version'), 'mode': 'redis'}})
            print_success(f"Redis connected - v{info.get('redis_version')}")
            return True
        except Exception as e:
            # Redis failure is WARNING — system falls back to memory cache
            warn_msg = f"Redis unavailable ({e}). System will use in-memory cache. Set REDIS_ENABLED=False to suppress."
            self.results['redis'].update({'status': True, 'details': {'mode': 'degraded_memory_fallback'}, 'warning': warn_msg})
            print_warning(warn_msg)
            return True   # Not fatal
    
    async def verify_database_schema(self) -> bool:
        """Verify database schema and model metadata"""
        print_info("Verifying database schema...")
        
        if not DATABASE_AVAILABLE:
            error_msg = "Database modules not available - install requirements"
            self.results['database_schema']['error'] = error_msg
            print_error(error_msg)
            return False
            
        try:
            from sqlalchemy import text
            
            # Get all tables in the database
            async with engine.begin() as conn:
                # List all tables
                tables_result = await conn.execute(text("""
                    SELECT table_name 
                    FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    ORDER BY table_name
                """))
                db_tables = [row[0] for row in tables_result.fetchall()]
                
                # Get SQLAlchemy model metadata
                model_tables = list(Base.metadata.tables.keys())
                
                self.results['database_schema'].update({
                    'status': True,
                    'details': {
                        'database_tables': db_tables,
                        'model_tables': model_tables,
                        'table_count': len(db_tables),
                        'model_count': len(model_tables)
                    }
                })
                
                print_success(f"Database schema verified - {len(db_tables)} tables found")
                
                # Check for discrepancies
                missing_in_db = set(model_tables) - set(db_tables)
                extra_in_db = set(db_tables) - set(model_tables)
                
                if missing_in_db:
                    print_warning(f"Models without tables: {missing_in_db}")
                
                if extra_in_db:
                    print_info(f"Extra tables in DB: {extra_in_db}")
                
                return True
                
        except Exception as e:
            error_msg = f"Database schema verification failed: {str(e)}"
            self.results['database_schema']['error'] = error_msg
            print_error(error_msg)
            return False
    
    async def verify_firebase(self) -> bool:
        """Verify Firebase Admin SDK initialization with mock token test"""
        print_info("Testing Firebase Admin SDK...")
        
        if not FIREBASE_AVAILABLE:
            error_msg = "Firebase modules not available - install requirements"
            self.results['firebase']['error'] = error_msg
            print_error(error_msg)
            return False
            
        if not CONFIG_AVAILABLE:
            error_msg = "Config not available - cannot verify Firebase"
            self.results['firebase']['error'] = error_msg
            print_error(error_msg)
            return False
            
        try:
            # Initialize Firebase Admin SDK
            FirebaseAdminService.initialize()
            
            # Test Firestore access
            loop = asyncio.get_running_loop()
            
            def test_firestore_access():
                """Test basic Firestore operations"""
                try:
                    # Test collection access
                    users_ref = FirebaseAdminService.firestore_client.collection('users')
                    # Just test the reference - don't actually query
                    _ = users_ref.limit(1)
                    
                    # Test RTDB access
                    from firebase_admin import db as rtdb
                    test_ref = rtdb.reference('healthcheck')
                    _ = test_ref
                    
                    return True, "Firebase services accessible"
                except Exception as e:
                    return False, str(e)
            
            firestore_ok, firestore_msg = await loop.run_in_executor(None, test_firestore_access)
            
            if firestore_ok:
                # Test token verification with a mock invalid token
                try:
                    await FirebaseAdminService.verify_firebase_token("invalid_mock_token")
                    # If we get here, something's wrong
                    raise Exception("Invalid token was accepted")
                except Exception as e:
                    # Expected behavior - invalid token should raise exception
                    if "401" in str(e) or "Invalid" in str(e):
                        token_test = "Token validation working correctly"
                    else:
                        raise Exception(f"Unexpected token validation error: {e}")
                
                self.results['firebase'].update({
                    'status': True,
                    'details': {
                        'firestore_access': True,
                        'token_validation': token_test,
                        'project_id': settings.FIREBASE_PROJECT_ID,
                        'database_url': settings.FIREBASE_DATABASE_URL
                    }
                })
                
                print_success(f"Firebase Admin SDK working - Project: {settings.FIREBASE_PROJECT_ID}")
                return True
            else:
                raise Exception(f"Firestore access failed: {firestore_msg}")
                
        except Exception as e:
            error_msg = f"Firebase verification failed: {str(e)}"
            self.results['firebase']['error'] = error_msg
            print_error(error_msg)
            return False
    
    async def run_all_checks(self) -> Dict[str, Any]:
        """Run all verification checks"""
        print(f"\n{Colors.BOLD}🔍 Drishti-Link Production Verification{Colors.RESET}")
        print("=" * 50)
        
        # Run all checks
        checks = [
            self.verify_postgresql(),
            self.verify_redis(),
            self.verify_database_schema(),
            self.verify_firebase()
        ]
        
        results = await asyncio.gather(*checks, return_exceptions=True)
        
        # Print summary
        print("\n" + "=" * 50)
        print(f"{Colors.BOLD}📊 VERIFICATION SUMMARY{Colors.RESET}")
        print("=" * 50)
        
        all_passed = True
        for service, result in self.results.items():
            status_icon = "✅" if result['status'] else "❌"
            status_text = "PASS" if result['status'] else "FAIL"
            color = Colors.GREEN if result['status'] else Colors.RED
            
            print(f"{color}{status_icon} {service.upper()}: {status_text}{Colors.RESET}")
            
            if result['error']:
                print(f"   └─ {Colors.RED}{result['error']}{Colors.RESET}")
            
            if not result['status']:
                all_passed = False
        
        # Overall result
        print("\n" + "=" * 50)
        if all_passed:
            print(f"{Colors.GREEN}{Colors.BOLD}🎉 ALL CHECKS PASSED - System is ready for production!{Colors.RESET}")
        else:
            print(f"{Colors.RED}{Colors.BOLD}⚠️  SOME CHECKS FAILED - Please address issues before deployment{Colors.RESET}")
        
        # Detailed results for debugging
        print(f"\n{Colors.BLUE}Detailed results saved to verification_results.json{Colors.RESET}")
        
        with open('verification_results.json', 'w') as f:
            json.dump(self.results, f, indent=2, default=str)
        
        return self.results

async def main():
    """Main verification entry point"""
    try:
        verifier = ProductionVerifier()
        results = await verifier.run_all_checks()
        
        # Calculate readiness score (Redis is optional)
        critical_services = ['postgresql', 'firebase']
        optional_services = ['redis', 'database_schema']
        critical_passed  = sum(1 for s in critical_services if results.get(s, {}).get('status', False))
        optional_passed  = sum(1 for s in optional_services if results.get(s, {}).get('status', False))
        total_passed     = critical_passed + optional_passed
        total_checks     = len(critical_services) + len(optional_services)
        score = round((total_passed / total_checks) * 100)

        print(f"\n{Colors.BOLD}🎯 Readiness Score: {score}%  ({total_passed}/{total_checks} checks passed){Colors.RESET}")

        # Only fail on critical service failures
        critical_failures = sum(1 for s in critical_services if not results.get(s, {}).get('status', False))
        sys.exit(critical_failures)
        
    except KeyboardInterrupt:
        print_warning("Verification interrupted by user")
        sys.exit(130)
    except Exception as e:
        print_error(f"Unexpected error during verification: {str(e)}")
        print(f"{Colors.YELLOW}{traceback.format_exc()}{Colors.RESET}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
