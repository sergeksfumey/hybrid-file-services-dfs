# DFS Design Guide -- Hybrid File Services

## DFS Namespace Sizing

Namespace server hardware (FR01FS001, FR01FS002):
- OS: Windows Server 2025 Datacenter
- RAM: 16 GB minimum (32 GB recommended for large namespaces)
- CPU: 4 cores minimum
- Storage:
  - C: 128 GB (OS)
  - D: Size to hold all DFS-R replicated content + 20% headroom
  - E: Size for Azure File Sync hot cache + 20% headroom (cold data tiered to Azure)

## DFS-R Replication Scheduling

Business hours (08:00-18:00): 512 Kbps maximum bandwidth per connection
Off-hours (18:00-08:00): unlimited bandwidth
Weekend: unlimited bandwidth

Monitor DFS-R health: dfsrdiag syncnow and Get-DfsrState

## Site Costing for Branch Optimisation

Configure AD Sites and Services for each branch office subnet.
Set DFS site link costs to prefer local server:
- Same-site access: cost 0 (always use local server)
- Cross-site fallback: cost 100 (use remote server only if local unavailable)

## DFS Namespace Referrals

Referral cache timeout: 1800 seconds (30 minutes) -- reduces NS server load
Target ordering: Lowest cost referrals first (site-aware)
Client failback: enabled -- clients return to preferred server when available

## Azure File Sync Integration with DFS

Recommended namespace design for Azure File Sync integration:
- Keep DFS-R replicated shares on D: volume
- Configure Azure File Sync on separate E: volume
- Create separate DFS folder targets for Azure File Sync path if needed
- Do NOT point DFS-R folder targets at Azure File Sync server endpoint paths

DFS namespace can safely include both:
- \\corp\shares\dfs-content --> D: (DFS-R replicated, no File Sync)
- \\corp\shares\cloud-content --> E: (Azure File Sync, no DFS-R)
