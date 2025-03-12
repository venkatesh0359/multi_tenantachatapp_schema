CREATE TABLE tenant_users (
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE RESTRICT, 
  is_active BOOLEAN DEFAULT TRUE,  -- Added for soft deletion
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deactivated_at TIMESTAMP WITH TIME ZONE DEFAULT 'infinity'::timestamp,  
  PRIMARY KEY (tenant_id, user_id)
);

-- Create indexes
CREATE INDEX idx_tenant_users_user_id ON tenant_users(user_id);
CREATE INDEX idx_tenant_users_is_active ON tenant_users(is_active);
CREATE INDEX idx_tenant_users_tenant_id_active ON tenant_users(tenant_id, is_active);

-- Create a trigger function to handle user deletion
CREATE OR REPLACE FUNCTION handle_user_deletion()
RETURNS TRIGGER AS $
BEGIN
  -- Soft delete tenant_users records only if they're currently active
  UPDATE tenant_users
  SET is_active = FALSE,
      deactivated_at = CURRENT_TIMESTAMP
  WHERE user_id = OLD.id AND is_active = TRUE;
  
  RETURN OLD;
END;
$ LANGUAGE plpgsql;

-- Create a trigger on auth.users for soft deletion
CREATE TRIGGER before_user_delete
BEFORE DELETE ON auth.users
FOR EACH ROW
EXECUTE FUNCTION handle_user_deletion();

-- Enable Row Level Security
ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;

-- Users can view their own active tenant associations
CREATE POLICY view_own_tenant_associations ON tenant_users
FOR SELECT USING (
  auth.uid() = user_id AND is_active = TRUE
);

-- Users can view their own historical tenant associations
CREATE POLICY view_own_historical_tenant_associations ON tenant_users
FOR SELECT USING (
  auth.uid() = user_id AND is_active = FALSE
);

-- Super users can view all tenant associations (active and inactive)
CREATE POLICY super_user_view_tenant_users ON tenant_users
FOR SELECT USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Super users can insert tenant associations
CREATE POLICY super_user_insert_tenant_users ON tenant_users
FOR INSERT WITH CHECK (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Super users can update tenant associations
CREATE POLICY super_user_update_tenant_users ON tenant_users
FOR UPDATE USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Super users can soft-delete tenant associations
CREATE POLICY super_user_delete_tenant_users ON tenant_users
FOR UPDATE 
USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
)
WITH CHECK (
  NEW.is_active = FALSE
  AND NEW.deactivated_at IS NOT NULL
);

-- Tenant admins can view users in their tenant (active only)
CREATE POLICY tenant_admin_view_users ON tenant_users
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenant_users.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND tenant_roles.role_name = 'Admin'
  )
  AND is_active = TRUE
);

-- Tenant admins can view historical users in their tenant
CREATE POLICY tenant_admin_view_historical_users ON tenant_users
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenant_users.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND tenant_roles.role_name = 'Admin'
  )
  AND is_active = FALSE
);

-- Tenant admins can add users to their tenant
CREATE POLICY tenant_admin_add_users ON tenant_users
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenant_users.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND tenant_roles.role_name = 'Admin'
  )
);

-- Tenant admins can soft-delete users from their tenant
CREATE POLICY tenant_admin_soft_delete_users ON tenant_users
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenant_users.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND tenant_roles.role_name = 'Admin'
  )
  AND OLD.is_active = TRUE
  AND NEW.is_active = FALSE
  AND NEW.deactivated_at IS NOT NULL
);

-- Tenant admins can reactivate users in their tenant
CREATE POLICY tenant_admin_reactivate_users ON tenant_users
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenant_users.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND tenant_roles.role_name = 'Admin'
  )
  AND OLD.is_active = FALSE
  AND NEW.is_active = TRUE
  AND NEW.deactivated_at = 'infinity'::timestamp
);
