#!/bin/bash

# Path file yang akan dimodifikasi
FILES=(
    "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
    "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php"
    "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/NetworkController.php"
    "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/SettingsController.php"
    "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/DatabaseController.php"
    "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ScheduleController.php"
    "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/SubuserController.php"
)

TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")

echo "🚀 Memasang proteksi Anti Delete Server dan Anti Intip Panel..."

# Fungsi untuk backup file
backup_file() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        local backup_path="${file_path}.bak_${TIMESTAMP}"
        cp "$file_path" "$backup_path"
        echo "📦 Backup file dibuat: $backup_path"
    fi
}

# Fungsi untuk menambahkan proteksi authorization
add_protection() {
    local file_path=$1
    local file_name=$(basename "$file_path")
    
    case "$file_name" in
        "ServerDeletionService.php")
            backup_file "$file_path"
            cat > "$file_path" << 'EOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
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

        // 🔒 Proteksi: hanya Admin ID = 1 boleh menghapus server siapa saja.
        // Selain itu, user biasa hanya boleh menghapus server MILIKNYA SENDIRI.
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id ?? $server->user_id ?? ($server->owner?->id ?? null) ?? ($server->user?->id ?? null);

                if ($ownerId === null) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ: ɪɴꜰᴏʀᴍᴀꜱɪ ᴘᴇᴍɪʟɪᴋ ꜱᴇʀᴠᴇʀ ᴛɪᴅᴀᴋ ᴛᴇʀꜱᴇᴅɪᴀ.');
                }

                if ($ownerId !== $user->id) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅᴇɴɪᴇᴅ. ʜᴀɴʏᴀ ꜱᴇʀᴠᴇʀ ꜱᴇɴᴅɪʀɪ ʏᴀɴɢ ʙɪꜱᴀ ᴅɪ ʜᴀᴘᴜꜱ. ᴘʀᴏᴛᴇᴄᴛ ᴀᴄᴛɪᴠᴇ');
                }
            }
        }

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
            ;;

        "ServerController.php")
            backup_file "$file_path"
            cat > "$file_path" << 'EOF'
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
        // 🔒 Proteksi Anti Intip: Pastikan user hanya bisa akses server sendiri
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) { // Bukan admin super
                $ownerId = $server->owner_id ?? $server->user_id ?? ($server->owner?->id ?? null) ?? ($server->user?->id ?? null);
                
                if ($ownerId === null || $ownerId !== $user->id) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ. ʜᴀɴʏᴀ ʙɪꜱᴀ ᴍᴇʟɪʜᴀᴛ ꜱᴇʀᴠᴇʀ ꜱᴇɴᴅɪʀɪ. ᴘʀᴏᴛᴇᴄᴛ ᴀᴄᴛɪᴠᴇ');
                }
            }
        }

        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->toArray();
    }

    /**
     * Get server resource utilization.
     */
    public function utilization(GetServerRequest $request, Server $server): array
    {
        // 🔒 Proteksi Anti Intip: Pastikan user hanya bisa akses server sendiri
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id ?? $server->user_id ?? ($server->owner?->id ?? null) ?? ($server->user?->id ?? null);
                
                if ($ownerId === null || $ownerId !== $user->id) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ. ʜᴀɴʏᴀ ʙɪꜱᴀ ᴍᴇʟɪʜᴀᴛ ꜱᴇʀᴠᴇʀ ꜱᴇɴᴅɪʀɪ. ᴘʀᴏᴛᴇᴄᴛ ᴀᴄᴛɪᴠᴇ');
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
            echo "✅ Proteksi Anti Intip ServerController berhasil dipasang!"
            ;;

        "NetworkController.php")
            backup_file "$file_path"
            cat > "$file_path" << 'EOF'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Pterodactyl\Models\Server;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\NetworkService;
use Pterodactyl\Transformers\Api\Client\NetworkRuleTransformer;
use Pterodactyl\Http\Requests\Api\Client\Servers\Network\GetNetworkRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Network\StoreNetworkRequest;

class NetworkController extends ClientApiController
{
    /**
     * NetworkController constructor.
     */
    public function __construct(
        private DaemonServerRepository $daemonServerRepository,
        private NetworkService $networkService
    ) {
        parent::__construct();
    }

    /**
     * Get all network rules for a server.
     */
    public function index(GetNetworkRequest $request, Server $server): array
    {
        // 🔒 Proteksi Anti Intip: Pastikan user hanya bisa akses server sendiri
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id ?? $server->user_id ?? ($server->owner?->id ?? null) ?? ($server->user?->id ?? null);
                
                if ($ownerId === null || $ownerId !== $user->id) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ. ʜᴀɴʏᴀ ʙɪꜱᴀ ᴍᴇʟɪʜᴀᴛ ꜱᴇʀᴠᴇʀ ꜱᴇɴᴅɪʀɪ. ᴘʀᴏᴛᴇᴄᴛ ᴀᴄᴛɪᴠᴇ');
                }
            }
        }

        $rules = $server->allocations()->where('id', $server->allocation_id)->get();

        return $this->fractal->collection($rules)
            ->transformWith($this->getTransformer(NetworkRuleTransformer::class))
            ->toArray();
    }

    /**
     * Store a new network rule for the server.
     */
    public function store(StoreNetworkRequest $request, Server $server): array
    {
        // 🔒 Proteksi Anti Intip: Pastikan user hanya bisa akses server sendiri
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id ?? $server->user_id ?? ($server->owner?->id ?? null) ?? ($server->user?->id ?? null);
                
                if ($ownerId === null || $ownerId !== $user->id) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ. ʜᴀɴʏᴀ ʙɪꜱᴀ ᴍᴇʟɪʜᴀᴛ ꜱᴇʀᴠᴇʀ ꜱᴇɴᴅɪʀɪ. ᴘʀᴏᴛᴇᴄᴛ ᴀᴄᴛɪᴠᴇ');
                }
            }
        }

        $rule = $this->networkService->handle($request, $server);

        return $this->fractal->item($rule)
            ->transformWith($this->getTransformer(NetworkRuleTransformer::class))
            ->toArray();
    }
}
EOF
            echo "✅ Proteksi Anti Intip NetworkController berhasil dipasang!"
            ;;

        "SettingsController.php")
            backup_file "$file_path"
            cat > "$file_path" << 'EOF'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Pterodactyl\Models\Server;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\ReinstallServerService;
use Pterodactyl\Services\Servers\RenameService;
use Pterodactyl\Services\Servers\ServerDetailService;
use Pterodactyl\Http\Requests\Api\Client\Servers\Settings\RenameServerRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Settings\ReinstallServerRequest;

class SettingsController extends ClientApiController
{
    /**
     * SettingsController constructor.
     */
    public function __construct(
        private DaemonServerRepository $daemonServerRepository,
        private RenameService $renameService,
        private ReinstallServerService $reinstallServerService,
        private ServerDetailService $detailService
    ) {
        parent::__construct();
    }

    /**
     * Rename a server.
     */
    public function rename(RenameServerRequest $request, Server $server): array
    {
        // 🔒 Proteksi Anti Intip: Pastikan user hanya bisa akses server sendiri
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id ?? $server->user_id ?? ($server->owner?->id ?? null) ?? ($server->user?->id ?? null);
                
                if ($ownerId === null || $ownerId !== $user->id) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ. ʜᴀɴʏᴀ ʙɪꜱᴀ ᴍᴇʟɪʜᴀᴛ ꜱᴇʀᴠᴇʀ ꜱᴇɴᴅɪʀɪ. ᴘʀᴏᴛᴇᴄᴛ ᴀᴄᴛɪᴠᴇ');
                }
            }
        }

        $this->renameService->handle($server, $request->input('name'));

        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->toArray();
    }

    /**
     * Reinstall a server.
     */
    public function reinstall(ReinstallServerRequest $request, Server $server): array
    {
        // 🔒 Proteksi Anti Intip: Pastikan user hanya bisa akses server sendiri
        $user = Auth::user();
        
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id ?? $server->user_id ?? ($server->owner?->id ?? null) ?? ($server->user?->id ?? null);
                
                if ($ownerId === null || $ownerId !== $user->id) {
                    throw new DisplayException('ᴀᴋꜱᴇꜱ ᴅɪᴛᴏʟᴀᴋ. ʜᴀɴʏᴀ ʙɪꜱᴀ ᴍᴇʟɪʜᴀᴛ ꜱᴇʀᴠᴇʀ ꜱᴇɴᴅɪʀɪ. ᴘʀᴏᴛᴇᴄᴛ ᴀᴄᴛɪᴠᴇ');
                }
            }
        }

        $this->reinstallServerService->reinstall($server);

        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->toArray();
    }
}
EOF
            echo "✅ Proteksi Anti Intip SettingsController berhasil dipasang!"
            ;;

        *)
            echo "⚠️ File $file_name tidak dikenali, dilewati..."
            ;;
    esac

    # Set permissions yang tepat
    if [ -f "$file_path" ]; then
        chmod 644 "$file_path"
        chown www-data:www-data "$file_path" 2>/dev/null || true
    fi
}

# Eksekusi proteksi untuk semua file
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        add_protection "$file"
    else
        echo "⚠️ File $file tidak ditemukan, dilewati..."
    fi
done

echo ""
echo "🎉 Semua proteksi berhasil dipasang!"
echo "🔒 Fitur yang aktif:"
echo "   ✅ Anti Delete Server (hanya server sendiri)"
echo "   ✅ Anti Intip Server List (hanya server sendiri)" 
echo "   ✅ Anti Intip Network Settings (hanya server sendiri)"
echo "   ✅ Anti Intip Server Settings (hanya server sendiri)"
echo "   🛡️  Hanya Admin (ID 1) yang bisa akses semua server"
echo ""
echo "📂 Backup file lama disimpan dengan extension: .bak_${TIMESTAMP}"
echo "🚀 Restart services mungkin diperlukan: systemctl restart pteroq"
