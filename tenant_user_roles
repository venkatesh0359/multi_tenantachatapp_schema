CREATE TABLE tenant_user_roles (
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id UUID REFERENCES tenant_roles(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (tenant_id, user_id, role_id)
);

-- Create indexes
CREATE INDEX idx_tenant_user_roles_user_id ON tenant_user_roles(user_id);
CREATE INDEX idx_tenant_user_roles_role_id ON tenant_user_roles(role_id);

-- Enable Row Level Security
ALTER TABLE tenant_user_roles ENABLE ROW LEVEL SECURITY;

-- Users can view their own roles
CREATE POLICY view_own_roles ON tenant_user_roles
FOR SELECT USING (auth.uid() = user_id);

-- Super users can manage all user roles - IMPROVED with EXISTS and WITH CHECK
CREATE POLICY super_user_manage_user_roles ON tenant_user_roles
FOR ALL 
USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
)
WITH CHECK (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
);

-- Tenant admins can manage user roles in their tenant - admin/any system role can do this
CREATE POLICY tenant_admin_manage_user_roles ON tenant_user_roles
FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles AS tur
    JOIN tenant_roles tr ON tr.id = tur.role_id
    WHERE tur.tenant_id = tenant_user_roles.tenant_id
    AND tur.user_id = auth.uid()
    AND (
      tr.role_name = 'Admin' OR tr.is_system_role = TRUE
    )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM tenant_user_roles AS tur
    JOIN tenant_roles tr ON tr.id = tur.role_id
    WHERE tur.tenant_id = tenant_user_roles.tenant_id
    AND tur.user_id = auth.uid()
    AND (
      tr.role_name = 'Admin' OR tr.is_system_role = TRUE
    )
  )
);
