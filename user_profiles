CREATE TABLE user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_url TEXT,
  is_super_user BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_user_profiles_is_super_user ON user_profiles(is_super_user) WHERE is_super_user = TRUE;

-- Create a function and trigger to auto-update the timestamp
CREATE OR REPLACE FUNCTION update_timestamp() 
RETURNS TRIGGER AS $
BEGIN
  NEW.updated_at = clock_timestamp();
  RETURN NEW;
END;
$ LANGUAGE plpgsql;

CREATE TRIGGER set_timestamp
BEFORE UPDATE ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

-- Enable Row Level Security
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Users can view their own profile
CREATE POLICY view_own_profile ON user_profiles
FOR SELECT USING (auth.uid() = id);

-- Users can update their own profile, but cannot change is_super_user
CREATE POLICY update_own_profile ON user_profiles
FOR UPDATE 
USING (auth.uid() = id)
WITH CHECK (is_super_user = OLD.is_super_user);

-- Super users can view all profiles
CREATE POLICY super_user_view_profiles ON user_profiles
FOR SELECT USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Super users can update profiles
CREATE POLICY super_user_update_profiles ON user_profiles
FOR UPDATE USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);
