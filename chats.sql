-- Create the chats table with partitioning by half-year (6 months)
CREATE TABLE chats (
  id UUID NOT NULL,
  tenant_id UUID NOT NULL,
  user_id UUID NOT NULL,
  title TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  archived BOOLEAN DEFAULT FALSE,
  archived_at TIMESTAMP WITH TIME ZONE,
  PRIMARY KEY(id, created_at)
) PARTITION BY RANGE (created_at);

-- Create default partition
CREATE TABLE chats_default PARTITION OF chats DEFAULT;

-- Create indexes on parent table
CREATE INDEX idx_chats_tenant_id_user_id ON chats(tenant_id, user_id);
CREATE INDEX idx_chats_created_at_tenant ON chats(created_at, tenant_id);
CREATE INDEX idx_chats_archived ON chats(archived);
CREATE INDEX idx_chats_id ON chats(id);  -- Index for quicker id-only lookups

-- Add foreign key constraints
ALTER TABLE chats ADD CONSTRAINT fk_chats_tenant
  FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;
  
ALTER TABLE chats ADD CONSTRAINT fk_chats_user
  FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- Create initial partitions for current half-year and next half-year
DO $
DECLARE
  current_year INTEGER := EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER;
  current_half INTEGER := CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) >= 7 THEN 2 ELSE 1 END;
  next_year INTEGER := current_year;
  next_half INTEGER := current_half + 1;
  current_start DATE;
  current_end DATE;
  next_start DATE;
  next_end DATE;
  current_partition_name TEXT;
  next_partition_name TEXT;
BEGIN
  -- Adjust next half-year if crosses year boundary
  IF next_half > 2 THEN
    next_half := 1;
    next_year := current_year + 1;
  END IF;
  
  -- Calculate current half-year dates
  IF current_half = 1 THEN
    current_start := make_date(current_year, 1, 1);
    current_end := make_date(current_year, 7, 1);
  ELSE
    current_start := make_date(current_year, 7, 1);
    current_end := make_date(current_year + 1, 1, 1);
  END IF;
  
  -- Calculate next half-year dates
  IF next_half = 1 THEN
    next_start := make_date(next_year, 1, 1);
    next_end := make_date(next_year, 7, 1);
  ELSE
    next_start := make_date(next_year, 7, 1);
    next_end := make_date(next_year + 1, 1, 1);
  END IF;
  
  -- Set partition names
  current_partition_name := format('chats_%s_h%s', current_year, current_half);
  next_partition_name := format('chats_%s_h%s', next_year, next_half);
  
  -- Create current half-year partition if it doesn't exist
  PERFORM 1
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relname = current_partition_name AND n.nspname = 'public';
  
  IF NOT FOUND THEN
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF chats FOR VALUES FROM (%L) TO (%L)',
      current_partition_name, current_start, current_end
    );
    
    RAISE NOTICE 'Created partition % for period % to %',
                 current_partition_name, current_start, current_end;
  END IF;
  
  -- Create next half-year partition if it doesn't exist
  PERFORM 1
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relname = next_partition_name AND n.nspname = 'public';
  
  IF NOT FOUND THEN
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF chats FOR VALUES FROM (%L) TO (%L)',
      next_partition_name, next_start, next_end
    );
    
    RAISE NOTICE 'Created partition % for period % to %',
                 next_partition_name, next_start, next_end;
  END IF;
END $;

-- Create function to automatically create partition indexes
CREATE OR REPLACE FUNCTION create_chat_partition_indexes(partition_name TEXT)
RETURNS VOID AS $$
BEGIN
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS %I ON %I(tenant_id, user_id)',
    'idx_' || partition_name || '_tenant_user', partition_name
  );
  
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS %I ON %I(created_at, tenant_id)',
    'idx_' || partition_name || '_created_at_tenant', partition_name
  );
  
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS %I ON %I(archived)',
    'idx_' || partition_name || '_archived', partition_name
  );
  
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS %I ON %I(id)',
    'idx_' || partition_name || '_id', partition_name
  );
END;
$$ LANGUAGE plpgsql;

-- Apply indexes to existing partitions
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE tablename LIKE 'chats_%'
  LOOP
    PERFORM create_chat_partition_indexes(r.tablename);
  END LOOP;
END $$;

-- Function to create half-year (6-month) partitions
CREATE OR REPLACE FUNCTION create_halfyear_chat_partition()
RETURNS TRIGGER AS $
DECLARE
  partition_year INTEGER;
  partition_half INTEGER;
  partition_name TEXT;
  start_date DATE;
  end_date DATE;
  next_partition_year INTEGER;
  next_partition_half INTEGER;
  next_partition_name TEXT;
  next_start_date DATE;
  next_end_date DATE;
BEGIN
  -- Calculate the half-year period
  partition_year := EXTRACT(YEAR FROM NEW.created_at)::INTEGER;
  partition_half := CASE WHEN EXTRACT(MONTH FROM NEW.created_at) >= 7 THEN 2 ELSE 1 END;
  
  -- Calculate start and end dates
  IF partition_half = 1 THEN
    start_date := make_date(partition_year, 1, 1);
    end_date := make_date(partition_year, 7, 1);
  ELSE
    start_date := make_date(partition_year, 7, 1);
    end_date := make_date(partition_year + 1, 1, 1);
  END IF;
  
  -- Format partition name: chats_YYYY_h1 or chats_YYYY_h2
  partition_name := format('chats_%s_h%s', partition_year, partition_half);
  
  -- Check if partition exists
  PERFORM 1
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relname = partition_name AND n.nspname = 'public';
  
  IF NOT FOUND THEN
    -- Create the partition
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF chats FOR VALUES FROM (%L) TO (%L)',
      partition_name, start_date, end_date
    );
    
    -- Create indexes
    PERFORM create_chat_partition_indexes(partition_name);
    
    RAISE NOTICE 'Created new partition % for period % to %', 
                 partition_name, start_date, end_date;
                 
    -- Calculate next half-year
    next_partition_half := partition_half + 1;
    next_partition_year := partition_year;
    
    -- Adjust if crossing year boundary
    IF next_partition_half > 2 THEN
      next_partition_half := 1;
      next_partition_year := partition_year + 1;
    END IF;
    
    -- Calculate next half-year dates
    IF next_partition_half = 1 THEN
      next_start_date := make_date(next_partition_year, 1, 1);
      next_end_date := make_date(next_partition_year, 7, 1);
    ELSE
      next_start_date := make_date(next_partition_year, 7, 1);
      next_end_date := make_date(next_partition_year + 1, 1, 1);
    END IF;
    
    -- Format next partition name
    next_partition_name := format('chats_%s_h%s', next_partition_year, next_partition_half);
    
    -- Check if next partition exists
    PERFORM 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = next_partition_name AND n.nspname = 'public';
    
    IF NOT FOUND THEN
      EXECUTE format(
        'CREATE TABLE %I PARTITION OF chats FOR VALUES FROM (%L) TO (%L)',
        next_partition_name, next_start_date, next_end_date
      );
      
      -- Create indexes
      PERFORM create_chat_partition_indexes(next_partition_name);
      
      RAISE NOTICE 'Proactively created next partition % for period % to %', 
                  next_partition_name, next_start_date, next_end_date;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$ LANGUAGE plpgsql;

-- Create trigger for automatic partition creation
CREATE TRIGGER trigger_create_chat_partition
BEFORE INSERT ON chats
FOR EACH ROW
EXECUTE FUNCTION create_halfyear_chat_partition();

-- Function to manage data in default partition
CREATE OR REPLACE FUNCTION manage_default_chat_partition(
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_DATE - INTERVAL '6 months',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_DATE,
  p_batch_size INTEGER DEFAULT 100,
  p_max_rows INTEGER DEFAULT 1000,
  p_dry_run BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
  partition_name TEXT,
  rows_moved INTEGER
) AS $
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE := p_start_date;
  v_end_date TIMESTAMP WITH TIME ZONE := p_end_date;
  v_partition_name TEXT;
  v_year INTEGER;
  v_half INTEGER;
  v_start_half DATE;
  v_end_half DATE;
  v_rows_moved INTEGER := 0;
  v_batch_moved INTEGER;
  v_total_rows INTEGER;
  v_half_record RECORD;
BEGIN
  -- Count total eligible rows
  EXECUTE 'SELECT COUNT(*) FROM chats_default WHERE created_at BETWEEN $1 AND $2'
  INTO v_total_rows
  USING v_start_date, v_end_date;
  
  RAISE NOTICE 'Found % rows in default partition between % and %', 
               v_total_rows, v_start_date, v_end_date;
               
  -- If dry run, return estimate only
  IF p_dry_run THEN
    RETURN QUERY SELECT 'DRY RUN'::TEXT, v_total_rows;
    RETURN;
  END IF;
  
  -- Get distinct half-years to identify needed partitions
  FOR v_half_record IN 
    EXECUTE 'SELECT 
              EXTRACT(YEAR FROM created_at)::INTEGER AS year,
              CASE WHEN EXTRACT(MONTH FROM created_at) >= 7 THEN 2 ELSE 1 END AS half
             FROM chats_default 
             WHERE created_at BETWEEN $1 AND $2
             GROUP BY year, half
             ORDER BY year, half'
    USING v_start_date, v_end_date
  LOOP
    v_year := v_half_record.year;
    v_half := v_half_record.half;
    
    -- Calculate half-year dates
    IF v_half = 1 THEN
      v_start_half := make_date(v_year, 1, 1);
      v_end_half := make_date(v_year, 7, 1);
    ELSE
      v_start_half := make_date(v_year, 7, 1);
      v_end_half := make_date(v_year + 1, 1, 1);
    END IF;
    
    -- Format partition name
    v_partition_name := format('chats_%s_h%s', v_year, v_half);
    
    -- Check if partition exists
    PERFORM 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = v_partition_name AND n.nspname = 'public';
    
    -- If partition doesn't exist, create it
    IF NOT FOUND THEN
      RAISE NOTICE 'Creating missing partition % for period % to %', 
                   v_partition_name, v_start_half, v_end_half;
                   
      EXECUTE format(
        'CREATE TABLE %I PARTITION OF chats FOR VALUES FROM (%L) TO (%L)',
        v_partition_name, v_start_half, v_end_half
      );
      
      PERFORM create_chat_partition_indexes(v_partition_name);
    END IF;
    
    -- Move data in batches
    v_rows_moved := 0;
    
    WHILE v_rows_moved < p_max_rows LOOP
      -- Create temp table for this batch
      CREATE TEMP TABLE temp_batch AS
      SELECT *
      FROM chats_default
      WHERE created_at >= v_start_month
        AND created_at < v_end_month
      LIMIT p_batch_size;
      
      GET DIAGNOSTICS v_batch_moved = ROW_COUNT;
      
      -- Stop if no more rows
      IF v_batch_moved = 0 THEN
        EXIT;
      END IF;
      
      -- Delete from default partition
      DELETE FROM chats_default
      WHERE id IN (SELECT id FROM temp_batch);
      
      -- Insert into proper partition (automatically handled by constraint exclusion)
      INSERT INTO chats
      SELECT * FROM temp_batch;
      
      v_rows_moved := v_rows_moved + v_batch_moved;
      DROP TABLE temp_batch;
      
      RAISE NOTICE 'Moved % rows to partition %', v_batch_moved, v_partition_name;
      
      -- Check if we've hit the limit
      IF v_rows_moved >= p_max_rows THEN
        EXIT;
      END IF;
    END LOOP;
    
    -- Return result for this partition
    RETURN QUERY SELECT v_partition_name, v_rows_moved;
  END LOOP;
  
  -- Return empty result if nothing was moved
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'No records moved'::TEXT, 0;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to archive old partitions with optimization options
CREATE OR REPLACE FUNCTION archive_chat_partitions(
  p_months_to_keep INTEGER DEFAULT 24,  -- Keep 2 years of data
  p_archive_schema TEXT DEFAULT 'chat_archive',
  p_dry_run BOOLEAN DEFAULT TRUE,
  p_use_attach_partition BOOLEAN DEFAULT FALSE  -- Performance optimization option
)
RETURNS TABLE(
  partition_name TEXT,
  action TEXT,
  rows_affected BIGINT
) AS $$
DECLARE
  v_cutoff_date DATE;
  v_partition RECORD;
  v_row_count BIGINT;
  v_archive_table TEXT;
BEGIN
  -- Calculate cutoff date
  v_cutoff_date := date_trunc('month', CURRENT_DATE - (p_months_to_keep || ' months')::INTERVAL);
  
  -- Create archive schema if needed
  IF NOT p_dry_run THEN
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', p_archive_schema);
  END IF;
  
  -- Find partitions older than cutoff date
  FOR v_partition IN
    SELECT c.relname AS partition_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname LIKE 'chats_%' 
      AND c.relname != 'chats_default'
      AND n.nspname = 'public'
      AND (
        -- Extract year and half from partition name (format: chats_YYYY_hN)
        (substring(c.relname from 7 for 4)::INTEGER < EXTRACT(YEAR FROM v_cutoff_date)::INTEGER) OR
        (substring(c.relname from 7 for 4)::INTEGER = EXTRACT(YEAR FROM v_cutoff_date)::INTEGER AND
         substring(c.relname from 13 for 1)::INTEGER < CASE WHEN EXTRACT(MONTH FROM v_cutoff_date) >= 7 THEN 2 ELSE 1 END)
      )
    ORDER BY c.relname
  LOOP
    -- Count rows in partition
    EXECUTE format('SELECT COUNT(*) FROM %I', v_partition.partition_name) INTO v_row_count;
    
    -- Archive if not dry run
    IF NOT p_dry_run THEN
      v_archive_table := p_archive_schema || '.' || v_partition.partition_name;
      
      -- Decide whether to use copy or attach method based on parameter
      IF p_use_attach_partition THEN
        -- Create parent table in archive schema if it doesn't exist
        EXECUTE format(
          'CREATE TABLE IF NOT EXISTS %I.chats (LIKE public.chats INCLUDING ALL)',
          p_archive_schema
        );
        
        -- Detach from main table
        EXECUTE format(
          'ALTER TABLE public.chats DETACH PARTITION %I',
          v_partition.partition_name
        );
        
        -- Attach to archive table
        EXECUTE format(
          'ALTER TABLE %I.chats ATTACH PARTITION %I FOR VALUES FROM (%L) TO (%L)',
          p_archive_schema,
          v_partition.partition_name,
          -- Extract date range from partition name
          make_date(
            substring(v_partition.partition_name from 7 for 4)::INTEGER,
            substring(v_partition.partition_name from 12 for 2)::INTEGER,
            1
          ),
          make_date(
            CASE WHEN substring(v_partition.partition_name from 12 for 2)::INTEGER = 12 THEN
              substring(v_partition.partition_name from 7 for 4)::INTEGER + 1
            ELSE
              substring(v_partition.partition_name from 7 for 4)::INTEGER
            END,
            CASE WHEN substring(v_partition.partition_name from 12 for 2)::INTEGER = 12 THEN
              1
            ELSE
              substring(v_partition.partition_name from 12 for 2)::INTEGER + 1
            END,
            1
          )
        );
        
        RETURN QUERY SELECT 
          v_partition.partition_name, 
          'DETACH AND ATTACH TO ARCHIVE'::TEXT,
          v_row_count;
      ELSE
        -- Use copy method (safer but slower)
        -- Create archive table
        EXECUTE format(
          'CREATE TABLE IF NOT EXISTS %I (LIKE %I INCLUDING ALL)',
          v_archive_table,
          v_partition.partition_name
        );
        
        -- Copy data
        EXECUTE format(
          'INSERT INTO %I SELECT * FROM %I',
          v_archive_table,
          v_partition.partition_name
        );
        
        -- Drop original
        EXECUTE format('DROP TABLE %I', v_partition.partition_name);
        
        RETURN QUERY SELECT 
          v_partition.partition_name, 
          'COPIED TO ARCHIVE AND DROPPED'::TEXT,
          v_row_count;
      END IF;
    ELSE
      -- Dry run mode
      RETURN QUERY SELECT 
        v_partition.partition_name, 
        'WOULD ARCHIVE (DRY RUN)'::TEXT,
        v_row_count;
    END IF;
  END LOOP;
  
  RETURN;
END;
$$ LANGUAGE plpgsql;

-- Enable RLS
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;

-- Users can access their own chats
CREATE POLICY user_access_own_chats ON chats
FOR ALL USING (
  auth.uid() = user_id AND
  EXISTS (
    SELECT 1 FROM tenant_users
    WHERE tenant_users.tenant_id = chats.tenant_id
    AND tenant_users.user_id = auth.uid()
  )
);

-- Super users can access all chats
CREATE POLICY super_user_access_chats ON chats
FOR ALL USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
);

-- Add audit logging for super user access
CREATE TABLE IF NOT EXISTS super_user_access_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_user_id UUID NOT NULL,
  accessed_tenant_id UUID NOT NULL,
  accessed_chat_id UUID,
  access_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  access_type TEXT
);

-- Create function to log super user access
CREATE OR REPLACE FUNCTION log_super_user_access()
RETURNS TRIGGER AS $$
DECLARE
  v_is_super_user BOOLEAN;
BEGIN
  -- Check if the current user is a super user
  SELECT is_super_user INTO v_is_super_user
  FROM user_profiles
  WHERE id = auth.uid();
  
  IF v_is_super_user THEN
    -- Log the access
    INSERT INTO super_user_access_logs (
      super_user_id,
      accessed_tenant_id,
      accessed_chat_id,
      access_type
    )
    VALUES (
      auth.uid(),
      NEW.tenant_id,
      NEW.id,
      TG_OP
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for super user access logging
CREATE TRIGGER log_super_user_chat_access
AFTER SELECT ON chats
FOR EACH ROW
EXECUTE FUNCTION log_super_user_access();

-- Tenant admins can access all chats in their tenant
CREATE POLICY tenant_admin_access_chats ON chats
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = chats.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND (
      tenant_roles.role_name = 'Admin' OR tenant_roles.is_system_role = TRUE
    )
  )
);

-- Helper function for efficient queries
CREATE OR REPLACE FUNCTION get_tenant_chats(
  p_tenant_id UUID,
  p_months_back INTEGER DEFAULT 3
)
RETURNS SETOF chats AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM chats
  WHERE tenant_id = p_tenant_id
  AND created_at > CURRENT_DATE - (p_months_back || ' months')::INTERVAL
  ORDER BY created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Add helpful comments
COMMENT ON TABLE chats IS 'Chat conversations with monthly time-based partitioning';

COMMENT ON FUNCTION manage_default_chat_partition(
  TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTEGER, INTEGER, BOOLEAN
) IS 
'Moves records from the default partition to their proper time partitions.
Parameters:
  p_start_date - Start date range for records to move (default: last month)
  p_end_date - End date range for records to move (default: current date)
  p_batch_size - Number of rows to move in each batch (default: 100)
  p_max_rows - Maximum number of rows to move (default: 1000)
  p_dry_run - If TRUE, only estimates rows without moving them (default: FALSE)

Example usage:
  -- Dry run to see how many rows would be affected
  SELECT * FROM manage_default_chat_partition(p_dry_run => TRUE);
  
  -- Actually move records with default settings
  SELECT * FROM manage_default_chat_partition();';

COMMENT ON FUNCTION archive_chat_partitions(INTEGER, TEXT, BOOLEAN, BOOLEAN) IS
'Archives old chat partitions to a separate schema.
Parameters:
  p_months_to_keep - Keep partitions newer than this many months (default: 24)
  p_archive_schema - Schema to use for archived tables (default: chat_archive)
  p_dry_run - If TRUE, report what would happen without making changes (default: TRUE)
  p_use_attach_partition - If TRUE, use ALTER TABLE ATTACH/DETACH for better performance (default: FALSE)

Example usage:
  -- Dry run to see what would be archived
  SELECT * FROM archive_chat_partitions();
  
  -- Archive partitions older than 12 months using the high-performance method
  SELECT * FROM archive_chat_partitions(
    p_months_to_keep => 12,
    p_dry_run => FALSE,
    p_use_attach_partition => TRUE
  );';
