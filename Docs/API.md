# 清风网盘接口清单（从 APK v1.3.0 静态提取）

来源：`com.qingfeng.netdisk` 1.3.0（versionCode 4），`classes.dex` 反编译后的 `Api.java`、
`Uploader.java`、`Thumbs.java`、`SettingsActivity.java`、`MemberDialog.java`。

## 通用约定

| 项目 | 值 |
|------|-----|
| Base URL | 客户端可配置，默认 `https://a131653141fe81eec.app.workbuddy.host` |
| 传输 | HTTP/HTTPS 明文与 TLS 均可（APK 设置 `usesCleartextTraffic=true`） |
| 方法 | GET 查询 / POST JSON / POST 二进制分片 |
| 认证头 | `X-QF-Token: <token>` 且 `Authorization: Bearer <token>`（两者同时发送） |
| 分享码 | 非空时自动追加 `?sharecode=<code>` 或 `&sharecode=<code>`，默认值 `AOMNHSOF2D` |
| 错误体 | 非 2xx 时读取 body `{"error": "..."}`，缺失时展示 `请求失败 (<status>)` |
| 超时 | 连接 15s；APK 读超时 120s（上传分片、下载同样适用） |
| 编码 | 查询参数 UTF-8 URL 编码 |
| JSON 解析 | 宽松解析：`id`/`size`/`is_folder` 等允许字符串形式数字 |

> 注意：原 APK 在两处把 token 直接拼进 URL query（`thumb` / `preview` / `download` 直链），
> 这是服务端支持的鉴权方式之一。iOS 版本保留该能力以驱动 `AVPlayer`/`AsyncImage`，
> 同时修正了分享码为空时拼出 `.../1&token=` 的畸形链接。

---

## 1. 认证

### POST /api/auth/login
```json
{"username": "alice", "password": "secret"}
```
响应：`{"token": "..."}`

### POST /api/auth/register
请求体同登录。响应：`{"token": "..."}`

### GET /api/me
响应字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `username` | string | 用户名 |
| `quota_bytes` | int64 | 总空间 |
| `used_bytes` | int64 | 已用空间 |
| `tier_name` | string | 会员等级名，默认「普通会员」 |
| `is_admin` | 0/1 | 是否管理员 |
| `tiers` | array | `[{name, quota_bytes}]` 等级列表 |

### GET /api/health
连通性探测（设置页），200 视为可用，无鉴权需求。

---

## 2. 文件

### GET /api/files/list?parentId=
`parentId` 为空表示根目录。响应：
```json
{"items": [{"id": 12, "name": "a.png", "is_folder": 0, "size": 1024, "mime": "image/png", "has_thumb": true}]}
```

### GET /api/search?q=<keyword>
响应同 `list`。

### GET /api/files/category?type=<image|video|doc|audio|zip>
响应同 `list`。

### GET /api/files/recent
响应同 `list`（首页取前 5 项）。

### POST /api/files/mkdir
```json
{"name": "新建文件夹", "parentId": 3}
```
`parentId` 省略表示根目录。

### POST /api/files/rename
```json
{"id": 12, "name": "新名字"}
```

### POST /api/files/delete
```json
{"ids": [12]}
```
软删除，进入回收站（响应通常为空 JSON `{}`）。

---

## 3. 回收站

### GET /api/trash/list
响应同 `list`，额外字段 `trashed_at`（ISO8601 字符串，客户端把 `T` 换成空格展示）。

### POST /api/trash/restore
```json
{"ids": [12, 13]}
```

### POST /api/trash/purge
```json
{"ids": [12]}
```
彻底删除并释放空间。

### POST /api/trash/empty
```json
{}
```

---

## 4. 上传（5MB 分片）

常量：`CHUNK = 5242880`；`totalChunks = max(1, ceil(size / CHUNK))`。

### POST /api/files/upload-init
```json
{"name": "big.iso", "size": 12582912, "parentId": 3, "totalChunks": 3}
```
响应：`{"uploadId": "..."}`

### POST /api/files/chunk?uploadId=<id>&index=<n>
`Content-Type: application/octet-stream`，body 为原始分片字节。
按 index 从 0 递增，逐片串行上传。

### POST /api/files/upload-complete
```json
{"uploadId": "..."}
```

---

## 5. 下载与预览

### GET /api/files/download/{id}
返回二进制流，`Content-Length` 用于进度。需要认证头（或 query `token`）。

### GET /api/files/preview/{id}
用于图片（`BitmapFactory`）、文本（<2MB 直接 UTF-8 解码）与音视频（交给 `VideoView`）预览。

### GET /api/files/thumb/{id}
返回 JPEG 缩略图；客户端内存 LRU + 磁盘缓存。

### 直链形式（供系统播放器 / 图片组件使用）
```
{server}/api/files/{preview|download|thumb}/{id}?sharecode=<code>&token=<token>
```

---

## 6. 分享

### POST /api/share/create
```json
{"id": 12, "password": "可选", "expireHours": 24}
```
响应：`{"shareUrl": "/s/xxxx"}`

客户端拼接：`<server><shareUrl>`，若分享码非空再追加 `?sharecode=<code>`，写入剪贴板。

---

## 7. 管理员

### GET /api/admin/users
响应：`{"users": [{"username": "bob", "tier_name": "普通会员", "used_bytes": 0, "quota_bytes": 5368709120}]}`

### POST /api/admin/set-quota
```json
{"username": "bob", "quota_bytes": 10737418240}
```
UI 以 GB 输入，客户端换算为字节（`GB * 1024^3`）。

---

## 8. 端点总表

| # | 方法 | 路径 | 认证 | 用途 |
|---|------|------|------|------|
| 1 | POST | /api/auth/login | 否 | 登录 |
| 2 | POST | /api/auth/register | 否 | 注册 |
| 3 | GET | /api/me | 是 | 用户信息与配额 |
| 4 | GET | /api/files/list | 是 | 列目录 |
| 5 | GET | /api/search | 是 | 搜索 |
| 6 | GET | /api/files/category | 是 | 按类型分类 |
| 7 | GET | /api/files/recent | 是 | 最近文件 |
| 8 | POST | /api/files/mkdir | 是 | 新建文件夹 |
| 9 | POST | /api/files/rename | 是 | 重命名 |
| 10 | POST | /api/files/delete | 是 | 移入回收站 |
| 11 | GET | /api/trash/list | 是 | 回收站列表 |
| 12 | POST | /api/trash/restore | 是 | 还原 |
| 13 | POST | /api/trash/purge | 是 | 彻底删除 |
| 14 | POST | /api/trash/empty | 是 | 清空回收站 |
| 15 | POST | /api/files/upload-init | 是 | 上传初始化 |
| 16 | POST | /api/files/chunk | 是 | 上传分片 |
| 17 | POST | /api/files/upload-complete | 是 | 上传完成 |
| 18 | GET | /api/files/download/{id} | 是 | 下载 |
| 19 | GET | /api/files/preview/{id} | 是 | 预览内容 |
| 20 | GET | /api/files/thumb/{id} | 是 | 缩略图 |
| 21 | POST | /api/share/create | 是 | 创建分享 |
| 22 | GET | /api/admin/users | 是 | 用户列表（管理员） |
| 23 | POST | /api/admin/set-quota | 是 | 设置配额（管理员） |
| 24 | GET | /api/health | 否 | 连通性检测 |
