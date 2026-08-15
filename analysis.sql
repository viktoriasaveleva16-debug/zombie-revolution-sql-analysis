-- =========================================================
-- Zombie Revolution SQL Analysis
-- User activity and session metrics
-- =========================================================


-- 1. Average session duration by month

select
    date_trunc('month', start_session) as month,
    avg(
        extract(epoch from end_session - start_session) / (60 * 60)
    ) as avg_session_hours
from skygame.game_sessions
where end_session - start_session > interval '5 minute'
group by month
order by month;


-- 2. Daily Active Users (DAU)

select
    start_session::date as activity_date,
    count(distinct id_user) as dau
from skygame.game_sessions
group by start_session::date
order by start_session::date;


-- 3. Weekly Active Users (WAU)

select
    date_trunc('week', start_session) as week,
    count(distinct id_user) as wau
from skygame.game_sessions
group by date_trunc('week', start_session)
order by date_trunc('week', start_session);


-- 4. Monthly Active Users (MAU)

select
    date_trunc('month', start_session) as month,
    count(distinct id_user) as mau
from skygame.game_sessions
group by date_trunc('month', start_session)
order by date_trunc('month', start_session);
-- =========================================================
-- 5. Technical issues
-- Sessions without an end time and OS breakdown
-- =========================================================

select
    count(*) as total_rows,

    sum(
        case
            when b.end_session is null then 1
            else 0
        end
    ) as problem_rows,

    sum(
        case
            when b.end_session is null then 1
            else 0
        end
    )::float / count(*) * 100 as share_total,

    sum(
        case
            when a.dev_type = 'ios'
             and b.end_session is null then 1
            else 0
        end
    )::float
    / sum(
        case
            when a.dev_type = 'ios' then 1
            else 0
        end
    ) * 100 as share_problem_ios,

    sum(
        case
            when a.dev_type = 'android'
             and b.end_session is null then 1
            else 0
        end
    )::float
    / sum(
        case
            when a.dev_type = 'android' then 1
            else 0
        end
    ) * 100 as share_problem_android,

    sum(
        case
            when a.dev_type = 'ios'
             and b.end_session is null then 1
            else 0
        end
    )::float
    / sum(
        case
            when b.end_session is null then 1
            else 0
        end
    ) * 100 as share_ios,

    sum(
        case
            when a.dev_type = 'android'
             and b.end_session is null then 1
            else 0
        end
    )::float
    / sum(
        case
            when b.end_session is null then 1
            else 0
        end
    ) * 100 as share_android

from skygame.users a
join skygame.game_sessions b
    on a.id_user = b.id_user;
-- =========================================================
-- 6. New acquisition channel
-- Users registered in November–December 2022
-- =========================================================

select
    case
        when u.reg_date >= '2022-11-01'
         and u.reg_date < '2023-01-01'
        then 1
        else 0
    end as cohort,

    count(distinct u.id_user) as cnt_users,

    avg(s.end_session - s.start_session) as avg_session_duration,

    extract(
        epoch from avg(s.end_session - s.start_session)
    ) / 60 as avg_session_minutes

from skygame.users as u

left join skygame.game_sessions as s
    on u.id_user = s.id_user
   and s.end_session - s.start_session > interval '5 minutes'

group by
    case
        when u.reg_date >= '2022-11-01'
         and u.reg_date < '2023-01-01'
        then 1
        else 0
    end

order by cohort;


-- =========================================================
-- 7. K-factor
-- Viral growth potential
-- =========================================================

select
    sum(r.ref_reg) * 1.0
        / count(distinct u.id_user) as k_factor,

    sum(r.ref_reg) * 1.0
        / count(
            distinct date_trunc('month', u.reg_date)
        ) as expected_future_cohort

from skygame.users as u

left join skygame.referral as r
    on u.id_user = r.id_user;
-- =========================================================
-- 8. Loyal users
-- Criterion 1: referrals
-- =========================================================

with crit_invite as (
    select
        id_user
    from skygame.referral
    group by id_user
    having count(*) >= 3
       and sum(ref_reg) >= 1
)

select
    date_trunc('month', gs.start_session) as month,
    count(distinct gs.id_user) as lmau_invite
from skygame.game_sessions gs
join crit_invite ci
    on gs.id_user = ci.id_user
group by month
order by month;


-- =========================================================
-- Criterion 2: payments >= 1000
-- =========================================================

with crit_1000 as (
    select
        m.id_user
    from skygame.monetary m
    join skygame.item_list i
        on m.id_item_buy = i.id_item
    join skygame.log_prices p
        on m.id_item_buy = p.id_item
       and m.dtime_pay >= p.valid_from
       and m.dtime_pay <= coalesce(p.valid_to, '3000-01-01')
    group by m.id_user
    having sum(m.cnt_buy * p.price) >= 1000
)

select
    date_trunc('month', gs.start_session) as month,
    count(distinct gs.id_user) as lmau_1000
from skygame.game_sessions gs
join crit_1000 c
    on gs.id_user = c.id_user
group by month
order by month;


-- =========================================================
-- Criterion 3: both conditions (AND)
-- =========================================================

with loyals1 as (
    select
        m.id_user
    from skygame.monetary m
    join skygame.item_list i
        on m.id_item_buy = i.id_item
    join skygame.log_prices p
        on m.id_item_buy = p.id_item
       and m.dtime_pay >= p.valid_from
       and m.dtime_pay <= coalesce(p.valid_to, '3000-01-01')
    group by m.id_user
    having sum(m.cnt_buy * p.price) >= 1000
),

loyals2 as (
    select
        id_user
    from skygame.referral
    group by id_user
    having count(*) >= 3
       and sum(ref_reg) >= 1
)

select
    date_trunc('month', gs.start_session) as month,
    count(distinct gs.id_user) as lmau_and
from skygame.game_sessions gs
where gs.id_user in (select id_user from loyals1)
  and gs.id_user in (select id_user from loyals2)
group by month
order by month;


-- =========================================================
-- Criterion 4: at least one condition (OR)
-- =========================================================

with loyals1 as (
    select
        m.id_user
    from skygame.monetary m
    join skygame.item_list i
        on m.id_item_buy = i.id_item
    join skygame.log_prices p
        on m.id_item_buy = p.id_item
       and m.dtime_pay >= p.valid_from
       and m.dtime_pay <= coalesce(p.valid_to, '3000-01-01')
    group by m.id_user
    having sum(m.cnt_buy * p.price) >= 1000
),

loyals2 as (
    select
        id_user
    from skygame.referral
    group by id_user
    having count(*) >= 3
       and sum(ref_reg) >= 1
)

select
    date_trunc('month', gs.start_session) as month,
    count(distinct gs.id_user) as lmau_or
from skygame.game_sessions gs
where gs.id_user in (select id_user from loyals1)
   or gs.id_user in (select id_user from loyals2)
group by month
order by month;
