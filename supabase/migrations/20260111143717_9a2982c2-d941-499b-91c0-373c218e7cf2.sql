-- Fix: Add created_at to get_referral_network_from_table function
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
    root_user_id uuid,
    p_max_levels integer DEFAULT 10,
    p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
    id uuid,
    full_name text,
    avatar_url text,
    level integer,
    parent_id uuid,
    subscription_status text,
    subscription_expires_at timestamp with time zone,
    personal_activation_volume numeric,
    has_commission_received boolean,
    no_commission_reason text,
    commission_frozen_until timestamp with time zone,
    is_activated boolean,
    created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE network AS (
        -- Base case: direct referrals of root user
        SELECT 
            rn.user_id,
            rn.referrer_id as parent_id,
            1 as lvl
        FROM referral_network rn
        WHERE rn.referrer_id = root_user_id
          AND rn.structure_type = p_structure_type
        
        UNION ALL
        
        -- Recursive case: referrals of referrals
        SELECT 
            rn.user_id,
            rn.referrer_id as parent_id,
            n.lvl + 1 as lvl
        FROM referral_network rn
        INNER JOIN network n ON rn.referrer_id = n.user_id
        WHERE rn.structure_type = p_structure_type
          AND n.lvl < p_max_levels
    )
    SELECT 
        n.user_id as id,
        p.full_name::text,
        p.avatar_url::text,
        n.lvl as level,
        n.parent_id,
        COALESCE(s.status, 'inactive')::text as subscription_status,
        s.expires_at as subscription_expires_at,
        COALESCE(ma.personal_volume, 0) as personal_activation_volume,
        -- Check if commission was received for this member from the root user
        EXISTS(
            SELECT 1 FROM transactions t 
            WHERE t.user_id = root_user_id 
              AND t.type = 'commission'
              AND t.status = 'completed'
              AND (t.payload->>'from_user_id')::uuid = n.user_id
        ) as has_commission_received,
        -- Get reason why commission was not received
        CASE 
            WHEN EXISTS(
                SELECT 1 FROM transactions t 
                WHERE t.user_id = root_user_id 
                  AND t.type = 'commission'
                  AND t.status = 'completed'
                  AND (t.payload->>'from_user_id')::uuid = n.user_id
            ) THEN NULL
            WHEN s.status IS NULL OR s.status != 'active' THEN 'inactive_subscription'
            WHEN ma.personal_volume IS NULL OR ma.personal_volume < 25000 THEN 'low_activation_volume'
            ELSE 'no_qualifying_orders'
        END::text as no_commission_reason,
        -- Check if commission is frozen
        (
            SELECT ct.frozen_until 
            FROM commission_thresholds ct 
            WHERE ct.user_id = root_user_id 
              AND ct.from_partner_id = n.user_id
              AND ct.frozen_until > NOW()
            ORDER BY ct.frozen_until DESC
            LIMIT 1
        ) as commission_frozen_until,
        -- Check if user is activated (has active subscription or met monthly activation)
        COALESCE(
            s.status = 'active' OR 
            (ma.personal_volume IS NOT NULL AND ma.personal_volume >= 25000),
            false
        ) as is_activated,
        p.created_at
    FROM network n
    LEFT JOIN profiles p ON p.id = n.user_id
    LEFT JOIN subscriptions s ON s.user_id = n.user_id
    LEFT JOIN monthly_activations ma ON ma.user_id = n.user_id 
        AND ma.month = date_trunc('month', CURRENT_DATE)::date
    ORDER BY n.lvl, p.full_name;
END;
$$;