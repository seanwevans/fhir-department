// src/hose.c

#include <ncurses.h>
#include <pthread.h>
#include <curl/curl.h>
#include <unistd.h>
#include <stdlib.h>
#include <locale.h>
#include <string.h>
#include <stdio.h>

#define NUM_SERVICES 16

// Service status codes:
// 0: querying (spinner shown)
// 1: running (✅)
// 2: down (❌)

typedef struct {
    const char *endpoint;
    volatile int status;
    int spinner_index;
    pthread_mutex_t lock;
} Service;

Service services[NUM_SERVICES];

void *poll_service(void *arg) {
    Service *svc = (Service *) arg;
    CURL *curl;
    CURLcode res;
    long response_code = 0;
    
    while (1) {
        pthread_mutex_lock(&svc->lock);
        svc->status = 0;
        pthread_mutex_unlock(&svc->lock);
        
        curl = curl_easy_init();
        if (curl) {
            curl_easy_setopt(curl, CURLOPT_URL, svc->endpoint);
            curl_easy_setopt(curl, CURLOPT_NOBODY, 1L); // Use HEAD request
            res = curl_easy_perform(curl);
            if (res == CURLE_OK) {
                curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
            }
            curl_easy_cleanup(curl);
        } else {
            res = CURLE_FAILED_INIT;
        }
        
        pthread_mutex_lock(&svc->lock);
        if (res == CURLE_OK && response_code == 200) {
            svc->status = 1; // running
        } else {
            svc->status = 2; // down
        }
        pthread_mutex_unlock(&svc->lock);
                
        sleep(10);
    }
    return NULL;
}

int main() {    
    setlocale(LC_ALL, "");    
    initscr();
    noecho();
    cbreak();
    curs_set(FALSE);
    nodelay(stdscr, TRUE);
    keypad(stdscr, TRUE);    
    curl_global_init(CURL_GLOBAL_ALL);
    
    for (int i = 0; i < NUM_SERVICES; i++) {
        char *url = malloc(64);    
        snprintf(url, 64, "http://localhost:8000/service%d", i);
        services[i].endpoint = url;
        services[i].status = 0; // start in querying state
        services[i].spinner_index = 0;
        pthread_mutex_init(&services[i].lock, NULL);
    }
    
    // Create a window for each microservice arranged in a 4x4 grid.
    int grid_rows = 4, grid_cols = 4;
    int win_height = 3, win_width = 7;
    WINDOW *wins[NUM_SERVICES];
    for (int i = 0; i < NUM_SERVICES; i++) {
        int r = i / grid_cols;
        int c = i % grid_cols;
        int start_y = r * win_height;
        int start_x = c * win_width;
        wins[i] = newwin(win_height, win_width, start_y, start_x);
        box(wins[i], 0, 0);
        wrefresh(wins[i]);
    }
    
    // Spawn a polling thread for each microservice.
    pthread_t threads[NUM_SERVICES];
    for (int i = 0; i < NUM_SERVICES; i++) {
        pthread_create(&threads[i], NULL, poll_service, &services[i]);
    }
    
    char *spinner[8] = {"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"};
        
    while (1) {
        for (int i = 0; i < NUM_SERVICES; i++) {
            int status;
            int sp_index;
            
            pthread_mutex_lock(&services[i].lock);
            status = services[i].status;
            sp_index = services[i].spinner_index;
            
            if (status == 0) {
                services[i].spinner_index = (services[i].spinner_index + 1) % 4;
                sp_index = services[i].spinner_index;
            }
            pthread_mutex_unlock(&services[i].lock);
            
            char *symbol;
            if (status == 0) {
                symbol = spinner[sp_index];
            } else if (status == 1) {
                symbol = "✅";
            } else {
                symbol = "❌";
            }
            
            werase(wins[i]);
            box(wins[i], 0, 0);
            
            int x_pos = (win_width - (int)strlen(symbol)) / 2;
            int y_pos = win_height / 2;
            mvwprintw(wins[i], y_pos, x_pos, "%s", symbol);
            wrefresh(wins[i]);
        }
        
        int ch = getch();
        if (ch == 'q' || ch == 'Q') {
            break;
        }
        
        usleep(100000);
    }
        
    endwin();
        
    for (int i = 0; i < NUM_SERVICES; i++) {
        pthread_cancel(threads[i]);
        pthread_mutex_destroy(&services[i].lock);
        free((void *)services[i].endpoint);
        delwin(wins[i]);
    }
    
    curl_global_cleanup();
    return 0;
}
