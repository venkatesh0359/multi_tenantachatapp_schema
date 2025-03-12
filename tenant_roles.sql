-- Create the tenant_roles table
CREATE TABLE tenant_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  role_name TEXT NOT NULL,
  description TEXT,
  permissions JSONB DEFAULT '{}' CHECK (jsonb_typeof(permissions) = 'object'),
  is_system_role BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(tenant_id, role_name)
);

-- Create indexes
CREATE INDEX idx_tenant_roles_tenant_id ON tenant_roles(tenant_id);

-- Enable Row Level Security
ALTER TABLE tenant_roles ENABLE ROW LEVEL SECURITY;

-- Users can view roles in their tenants
CREATE POLICY view_tenant_roles ON tenant_roles
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM tenant_users
    WHERE tenant_users.tenant_id = tenant_roles.tenant_id
    AND tenant_users.user_id = auth.uid()
    AND tenant_users.is_active = TRUE
  )
);

-- Super users can manage all roles - IMPROVED with EXISTS and WITH CHECK
CREATE POLICY super_user_manage_roles ON tenant_roles
FOR ALL 
USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
)
WITH CHECK (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
);

-- Tenant admins can manage roles in their tenant - IMPROVED to avoid hardcoding
CREATE POLICY tenant_admin_manage_roles ON tenant_roles
FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles AS tr ON tr.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenant_roles.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND (
      tr.role_name = 'Admin' OR tr.is_system_role = TRUE
    )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles AS tr ON tr.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenant_roles.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND (
      tr.role_name = 'Admin' OR tr.is_system_role = TRUE
    )
  )
);
