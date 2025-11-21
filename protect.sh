#!/bin/bash

# Path file utama yang akan dimodifikasi
FILES=(
    "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
    "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php"
)

TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")

echo "🚀 Memasang sistem proteksi KINZXXOFFC..."

# Fungsi untuk backup file
backup_file() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        local backup_path="${file_path}.bak_${TIMESTAMP}"
        cp "$file_path" "$backup_path"
        echo "📦 Backup file dibuat: $backup_path"
        return 0
    else
        echo "⚠️ File tidak ditemukan: $file_path"
        return 1
    fi
}

# Proteksi ServerDeletionService.php
if backup_file "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"; then
    cat > "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php" << 'EOF'
<?php

namespace Pterodactyl\Services\Servers;

use Pterodactyl\Models\User;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class ServerDeletionService
{
    protected bool $force = false;

    /**
     * ServerDeletionService constructor.
     */
    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private DatabaseManagementService $databaseManagementService
    ) {
    }

    /**
     * Set if the server should be forcibly deleted from the panel (ignoring daemon errors) or not.
     */
    public function withForce(bool $bool = true): self
    {
        $this->force = $bool;
        return $this;
    }

    /**
     * Delete a server from the panel and remove any associated databases from hosts.
     *
     * @throws \Throwable
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function handle(Server $server): void
    {
        $user = Auth::user();

        // 🔒 PROTECT BY KINZXXOFFC - ANTI DELETE SERVER ORANG
        // ===================================================
        // - Hanya Admin ID = 1 yang bisa hapus server siapa saja
        // - Admin panel lain & user TIDAK BISA hapus server user lain
        // - User hanya bisa hapus server milik sendiri
        // ===================================================
        
        if ($user) {
            if ($user->id !== 1) {
                // Untuk SEMUA user termasuk admin panel (selain ID 1) dan user biasa
                if (!$server->user || $server->user->id !== $user->id) {
                    throw new DisplayException('
╔═══════════════════════════════════════════════╗
║                𝗔𝗖𝗖𝗘𝗦𝗦 𝗗𝗘𝗡𝗜𝗘𝗗                ║
╠═══════════════════════════════════════════════╣
║ ❌ Hanya bisa menghapus server sendiri!       ║
║ 👤 User ID: ' . $user->id . '                                ║
║ 🖥️  Server Owner ID: ' . ($server->user ? $server->user->id : 'Unknown') . '                          ║
╠═══════════════════════════════════════════════╣
║         𝗣𝗥𝗢𝗧𝗘𝗖𝗧𝗘𝗗 𝗕𝗬 𝗞𝗜𝗡𝗭𝗫𝗫𝗢𝗙𝗙𝗖           ║
╚═══════════════════════════════════════════════╝
                    ');
                }
            }
            // Admin ID = 1 bisa lanjut tanpa pengecekan
        }

        // Log activity untuk audit
        Log::info("🛡️ PROTECT BY KINZXXOFFC - Server deletion attempted", [
            'user_id' => $user ? $user->id : 'unknown',
            'server_id' => $server->id,
            'server_owner' => $server->user ? $server->user->id : 'unknown',
            'action' => 'delete'
        ]);

        try {
            $this->daemonServerRepository->setServer($server)->delete();
        } catch (DaemonConnectionException $exception) {
            if (!$this->force && $exception->getStatusCode() !== Response::HTTP_NOT_FOUND) {
                throw $exception;
            }
            Log::warning($exception);
        }

        $this->connection->transaction(function () use ($server) {
            foreach ($server->databases as $database) {
                try {
                    $this->databaseManagementService->delete($database);
                } catch (\Exception $exception) {
                    if (!$this->force) {
                        throw $exception;
                    }
                    $database->delete();
                    Log::warning($exception);
                }
            }
            $server->delete();
        });
    }
}
EOF
    echo "✅ Proteksi Anti Delete Server berhasil dipasang!"
fi

# Proteksi ServerController.php
if backup_file "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php"; then
    cat > "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php" << 'EOF'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\ResourceUtilizationService;
use Pterodactyl\Transformers\Api\Client\ServerTransformer;
use Pterodactyl\Http\Requests\Api\Client\Servers\GetServerRequest;

class ServerController extends ClientApiController
{
    /**
     * ServerController constructor.
     */
    public function __construct(
        private DaemonServerRepository $daemonServerRepository,
        private ResourceUtilizationService $resourceUtilizationService
    ) {
        parent::__construct();
    }

    /**
     * Transform an individual server into a response that can be consumed by a
     * client using the API.
     */
    public function index(GetServerRequest $request, Server $server): array
    {
        // 🔒 PROTECT BY KINZXXOFFC - ANTI INTIP SERVER ORANG
        // ===================================================
        // - Hanya Admin ID = 1 yang bisa lihat server siapa saja
        // - Admin panel lain & user TIDAK BISA lihat server user lain
        // - User hanya bisa lihat server milik sendiri
        // ===================================================
        
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) {
                // Untuk SEMUA user termasuk admin panel (selain ID 1) dan user biasa
                if (!$server->user || $server->user->id !== $user->id) {
                    // Cek juga apakah user adalah subuser di server ini
                    $isSubuser = $server->subusers()->where('user_id', $user->id)->exists();
                    if (!$isSubuser) {
                        throw new DisplayException('
╔═══════════════════════════════════════════════╗
║                𝗔𝗖𝗖𝗘𝗦𝗦 𝗗𝗘𝗡𝗜𝗘𝗗                ║
╠═══════════════════════════════════════════════╣
║ ❌ Hanya bisa melihat server sendiri!         ║
║ 👤 User ID: ' . $user->id . '                                ║
║ 🖥️  Server Owner ID: ' . ($server->user ? $server->user->id : 'Unknown') . '                          ║
╠═══════════════════════════════════════════════╣
║         𝗣𝗥𝗢𝗧𝗘𝗖𝗧𝗘𝗗 𝗕𝗬 𝗞𝗜𝗡𝗭𝗫𝗫𝗢𝗙𝗙𝗖           ║
╚═══════════════════════════════════════════════╝
                        ');
                    }
                }
            }
            // Admin ID = 1 bisa lanjut tanpa pengecekan
        }

        // Log activity untuk audit
        \Illuminate\Support\Facades\Log::info("🛡️ PROTECT BY KINZXXOFFC - Server view attempted", [
            'user_id' => $user ? $user->id : 'unknown',
            'server_id' => $server->id,
            'server_owner' => $server->user ? $server->user->id : 'unknown',
            'action' => 'view'
        ]);

        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->toArray();
    }

    /**
     * Get server resource utilization.
     */
    public function utilization(GetServerRequest $request, Server $server): array
    {
        // 🔒 PROTECT BY KINZXXOFFC - ANTI INTIP RESOURCE ORANG
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) {
                if (!$server->user || $server->user->id !== $user->id) {
                    $isSubuser = $server->subusers()->where('user_id', $user->id)->exists();
                    if (!$isSubuser) {
                        throw new DisplayException('
╔═══════════════════════════════════════════════╗
║                𝗔𝗖𝗖𝗘𝗦𝗦 𝗗𝗘𝗡𝗜𝗘𝗗                ║
╠═══════════════════════════════════════════════╣
║ ❌ Hanya bisa monitor server sendiri!         ║
║ 👤 User ID: ' . $user->id . '                                ║
║ 🖥️  Server Owner ID: ' . ($server->user ? $server->user->id : 'Unknown') . '                          ║
╠═══════════════════════════════════════════════╣
║         𝗣𝗥𝗢𝗧𝗘𝗖𝗧𝗘𝗗 𝗕𝗬 𝗞𝗜𝗡𝗭𝗫𝗫𝗢𝗙𝗙𝗖           ║
╚═══════════════════════════════════════════════╝
                        ');
                    }
                }
            }
        }

        $utilization = $this->resourceUtilizationService->handle($server);

        return [
            'resources' => [
                'memory_bytes' => $utilization->memory,
                'cpu_absolute' => $utilization->cpu,
                'disk_bytes' => $utilization->disk,
                'network_rx_bytes' => $utilization->networkRx,
                'network_tx_bytes' => $utilization->networkTx,
            ],
        ];
    }
}
EOF
    echo "✅ Proteksi Anti Intip Server berhasil dipasang!"
fi

# Set permissions
chmod 644 "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
chmod 644 "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php"
chown www-data:www-data "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php" 2>/dev/null || true
chown www-data:www-data "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php" 2>/dev/null || true

echo ""
echo "🎉 SISTEM PROTEKSI KINZXXOFFC BERHASIL DIPASANG!"
echo ""
echo "🔒 FITUR YANG AKTIF:"
echo "   ✅ Anti Delete Server Orang"
echo "   ✅ Anti Intip Server Orang" 
echo "   ✅ Anti Monitor Resource Server Orang"
echo "   ✅ Tampilan Error Custom 'PROTECT BY KINZXXOFFC'"
echo "   ✅ Logging Activity untuk Audit"
echo ""
echo "👑 AKSES YANG DIIZINKAN:"
echo "   🏆 Admin ID 1 → Bisa akses semua server"
echo "   👤 User Biasa → Hanya server sendiri"
echo "   🔧 Admin Lain → Hanya server sendiri"
echo "   👥 Subuser → Bisa akses server yang di-share"
echo ""
echo "📂 Backup tersimpan di:"
echo "   /var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php.bak_${TIMESTAMP}"
echo "   /var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php.bak_${TIMESTAMP}"
echo ""
echo "🚀 Restart service:"
echo "   systemctl restart pteroq"
echo "   systemctl restart nginx"
echo ""
echo "🛡️  PROTECT BY KINZXXOFFC - SYSTEM SECURITY"
