#include <iostream>
#include <fstream>
#include <thread>
#include <chrono>
#include <dlfcn.h>
#include <cstring>

// Mono forward declarations
typedef struct _MonoDomain MonoDomain;
typedef struct _MonoAssembly MonoAssembly;
typedef struct _MonoImage MonoImage;
typedef struct _MonoTableInfo MonoTableInfo;

// Function pointers
MonoDomain* (*mono_get_root_domain)();
void (*mono_thread_attach)(MonoDomain*);
MonoAssembly** (*mono_domain_get_assemblies)(MonoDomain*, int*);
MonoImage* (*mono_assembly_get_image)(MonoAssembly*);
const char* (*mono_image_get_name)(MonoImage*);
const MonoTableInfo* (*mono_image_get_table_info)(MonoImage*, int);
int (*mono_table_info_get_rows)(const MonoTableInfo*);
void (*mono_metadata_decode_row)(const MonoTableInfo*, int, uint32_t*, int);
const char* (*mono_metadata_string_heap)(MonoImage*, uint32_t);

// Constants
#define MONO_TABLE_TYPEDEF 2
#define MONO_TYPEDEF_SIZE 6
#define MONO_TYPEDEF_NAME 1
#define MONO_TYPEDEF_NAMESPACE 2

// Logging helper
std::ofstream logFile;

#define LOG(x) logFile << x << std::endl;

// Resolve symbols
bool resolveSymbols() {
    void* handle = dlopen(NULL, RTLD_NOW);

    mono_get_root_domain = (MonoDomain* (*)())dlsym(handle, "mono_get_root_domain");
    mono_thread_attach = (void (*)(MonoDomain*))dlsym(handle, "mono_thread_attach");
    mono_domain_get_assemblies = (MonoAssembly** (*)(MonoDomain*, int*))dlsym(handle, "mono_domain_get_assemblies");
    mono_assembly_get_image = (MonoImage* (*)(MonoAssembly*))dlsym(handle, "mono_assembly_get_image");
    mono_image_get_name = (const char* (*)(MonoImage*))dlsym(handle, "mono_image_get_name");
    mono_image_get_table_info = (const MonoTableInfo* (*)(MonoImage*, int))dlsym(handle, "mono_image_get_table_info");
    mono_table_info_get_rows = (int (*)(const MonoTableInfo*))dlsym(handle, "mono_table_info_get_rows");
    mono_metadata_decode_row = (void (*)(const MonoTableInfo*, int, uint32_t*, int))dlsym(handle, "mono_metadata_decode_row");
    mono_metadata_string_heap = (const char* (*)(MonoImage*, uint32_t))dlsym(handle, "mono_metadata_string_heap");

    if (!mono_get_root_domain || !mono_thread_attach || !mono_domain_get_assemblies) {
        LOG("[FAIL] Failed resolving Mono symbols");
        return false;
    }

    return true;
}

// Path
std::string getPath() {
    const char* env = getenv("LC_SHARED_FOLDER");
    if (env) return std::string(env) + "/mono_classes.txt";
    return "/tmp/mono_classes.txt";
}

// Check if it's a game assembly
bool isGameAssembly(const char* name) {
    if (!name) return false;

    // Adjust this if needed
    return strstr(name, "Survivalcraft") != nullptr;
}

// Wait for Mono
MonoDomain* waitForMono() {
    MonoDomain* domain = nullptr;

    for (int i = 0; i < 15; i++) {
        domain = mono_get_root_domain();
        if (domain) return domain;

        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    LOG("[FAIL] Mono domain not found");
    return nullptr;
}

void dumpClasses() {
    std::string path = getPath();
    logFile.open(path);

    if (!logFile.is_open()) return;

    LOG("=== Mono Class Dump (Game Only) ===");

    if (!resolveSymbols()) return;

    MonoDomain* domain = waitForMono();
    if (!domain) return;

    mono_thread_attach(domain);

    int count = 0;
    MonoAssembly** assemblies = mono_domain_get_assemblies(domain, &count);

    if (!assemblies || count == 0) {
        LOG("[FAIL] No assemblies found");
        return;
    }

    LOG("[INFO] Total assemblies: " << count);

    for (int i = 0; i < count; i++) {
        MonoAssembly* assembly = assemblies[i];
        MonoImage* image = mono_assembly_get_image(assembly);

        if (!image) continue;

        const char* assemblyName = mono_image_get_name(image);
        if (!assemblyName) continue;

        // 🔥 FILTER HERE
        if (!isGameAssembly(assemblyName)) continue;

        LOG("\n[Game Assembly] " << assemblyName);

        const MonoTableInfo* table =
            mono_image_get_table_info(image, MONO_TABLE_TYPEDEF);

        if (!table) {
            LOG("[FAIL] No table for " << assemblyName);
            continue;
        }

        int rows = mono_table_info_get_rows(table);

        for (int j = 0; j < rows; j++) {
            uint32_t cols[MONO_TYPEDEF_SIZE];
            mono_metadata_decode_row(table, j, cols, MONO_TYPEDEF_SIZE);

            const char* name =
                mono_metadata_string_heap(image, cols[MONO_TYPEDEF_NAME]);

            const char* nspace =
                mono_metadata_string_heap(image, cols[MONO_TYPEDEF_NAMESPACE]);

            if (name && strlen(name) > 0) {
                LOG((nspace ? nspace : "") << "." << name);
            }
        }
    }

    LOG("\n[DONE]");
    logFile.close();
}

// Thread
void run() {
    std::this_thread::sleep_for(std::chrono::seconds(4));
    dumpClasses();
}

// Entry
__attribute__((constructor))
static void init() {
    std::thread(run).detach();
}
