-- FHIR House Data Management Schema
-- Based on the diagram showing databases in the FHIR House section

-- 1. Original Copy Database
-- Stores the original unmodified documents/data
CREATE TABLE original_copy (
    document_id VARCHAR(50) PRIMARY KEY,
    content BLOB NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_type VARCHAR(50) NOT NULL,
    file_size BIGINT NOT NULL,
    upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hash_value VARCHAR(128) NOT NULL,
    source_system VARCHAR(100),
    CONSTRAINT uc_original_hash UNIQUE (hash_value)
);

-- 2. Metadata Database
-- Stores metadata about documents and processing information
CREATE TABLE metadata (
    metadata_id VARCHAR(50) PRIMARY KEY,
    document_id VARCHAR(50) NOT NULL,
    title VARCHAR(255),
    author VARCHAR(100),
    created_date TIMESTAMP,
    document_type VARCHAR(50),
    patient_id VARCHAR(50),
    encounter_id VARCHAR(50),
    provider_id VARCHAR(50),
    organization_id VARCHAR(50),
    keywords TEXT,
    language VARCHAR(20),
    version VARCHAR(20),
    status VARCHAR(20),
    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_metadata_document FOREIGN KEY (document_id) REFERENCES original_copy(document_id)
);

CREATE INDEX idx_metadata_patient ON metadata(patient_id);
CREATE INDEX idx_metadata_document_type ON metadata(document_type);

-- 3. Backup Database
-- Stores backup data for disaster recovery
CREATE TABLE backup_schedule (
    schedule_id VARCHAR(50) PRIMARY KEY,
    backup_type VARCHAR(20) NOT NULL, -- full, incremental, differential
    frequency VARCHAR(50) NOT NULL, -- daily, weekly, monthly
    retention_period INT NOT NULL, -- days to keep backup
    last_execution TIMESTAMP,
    next_execution TIMESTAMP,
    status VARCHAR(20)
);

CREATE TABLE backup_log (
    backup_id VARCHAR(50) PRIMARY KEY,
    schedule_id VARCHAR(50) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    size_bytes BIGINT,
    location VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL,
    error_message TEXT,
    CONSTRAINT fk_backup_schedule FOREIGN KEY (schedule_id) REFERENCES backup_schedule(schedule_id)
);

-- 4. Process Control Database
-- Manages workflow and processing states
CREATE TABLE process_control (
    process_id VARCHAR(50) PRIMARY KEY,
    process_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    priority INT DEFAULT 5,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_timestamp TIMESTAMP,
    completed_timestamp TIMESTAMP,
    assigned_to VARCHAR(50),
    document_id VARCHAR(50),
    current_step VARCHAR(50),
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    error_message TEXT,
    CONSTRAINT fk_process_document FOREIGN KEY (document_id) REFERENCES original_copy(document_id)
);

CREATE TABLE process_steps (
    step_id VARCHAR(50) PRIMARY KEY,
    process_id VARCHAR(50) NOT NULL,
    step_name VARCHAR(50) NOT NULL,
    step_order INT NOT NULL,
    status VARCHAR(20) NOT NULL,
    started_timestamp TIMESTAMP,
    completed_timestamp TIMESTAMP,
    execution_time_ms INT,
    input_parameters TEXT,
    output_parameters TEXT,
    error_message TEXT,
    CONSTRAINT fk_steps_process FOREIGN KEY (process_id) REFERENCES process_control(process_id)
);

CREATE INDEX idx_process_status ON process_control(status);
CREATE INDEX idx_process_document ON process_control(document_id);

-- 5. Version Control Database
-- Manages different versions of processed documents
CREATE TABLE version_control (
    version_id VARCHAR(50) PRIMARY KEY,
    document_id VARCHAR(50) NOT NULL,
    version_number INT NOT NULL,
    content BLOB NOT NULL,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(50),
    change_summary TEXT,
    validation_status VARCHAR(20),
    confidence_score DECIMAL(5,2),
    is_current BOOLEAN DEFAULT FALSE,
    CONSTRAINT fk_version_document FOREIGN KEY (document_id) REFERENCES original_copy(document_id),
    CONSTRAINT uc_document_version UNIQUE (document_id, version_number)
);

CREATE INDEX idx_version_document ON version_control(document_id);
CREATE INDEX idx_version_current ON version_control(is_current);

-- 6. ML Models and Training Data Database
-- Stores ML models and the data used to train them

-- ML Model table - stores the models themselves
CREATE TABLE ml_models (
    model_id VARCHAR(50) PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    model_type VARCHAR(50) NOT NULL, -- classification, entity_extraction, etc.
    version VARCHAR(20) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT FALSE,
    is_production BOOLEAN DEFAULT FALSE,
    binary_data LONGBLOB NOT NULL, -- The serialized model itself
    model_format VARCHAR(50) NOT NULL, -- pickle, h5, onnx, etc.
    framework VARCHAR(50) NOT NULL, -- tensorflow, pytorch, sklearn, etc.
    parameters TEXT, -- JSON with hyperparameters
    size_bytes BIGINT,
    hash_value VARCHAR(128), -- Hash of the model binary for integrity verification
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(50),
    last_deployed_timestamp TIMESTAMP,
    last_trained_timestamp TIMESTAMP NOT NULL,
    training_duration_seconds INT,
    training_config TEXT, -- JSON configuration used for training
    evaluation_metrics TEXT, -- JSON with evaluation metrics
    accuracy DECIMAL(5,4),
    f1_score DECIMAL(5,4),
    precision_score DECIMAL(5,4),
    recall_score DECIMAL(5,4),
    parent_model_id VARCHAR(50), -- For tracking model lineage
    CONSTRAINT uc_model_name_version UNIQUE (model_name, version),
    CONSTRAINT fk_parent_model FOREIGN KEY (parent_model_id) REFERENCES ml_models(model_id)
);

-- Model dependencies/libraries
CREATE TABLE model_dependencies (
    dependency_id VARCHAR(50) PRIMARY KEY,
    model_id VARCHAR(50) NOT NULL,
    library_name VARCHAR(100) NOT NULL,
    version VARCHAR(50) NOT NULL,
    CONSTRAINT fk_dependency_model FOREIGN KEY (model_id) REFERENCES ml_models(model_id)
);

-- Model deployment history
CREATE TABLE model_deployments (
    deployment_id VARCHAR(50) PRIMARY KEY,
    model_id VARCHAR(50) NOT NULL,
    environment VARCHAR(50) NOT NULL, -- dev, test, production
    deployment_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deployed_by VARCHAR(50),
    status VARCHAR(20) NOT NULL, -- success, failed, rolled_back
    endpoint_url VARCHAR(255),
    config_parameters TEXT, -- JSON deployment parameters
    deployment_notes TEXT,
    CONSTRAINT fk_deployment_model FOREIGN KEY (model_id) REFERENCES ml_models(model_id)
);

-- Tracks which training sets were used for which models
CREATE TABLE model_training_sets (
    model_id VARCHAR(50) NOT NULL,
    set_id VARCHAR(50) NOT NULL,
    training_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (model_id, set_id),
    CONSTRAINT fk_training_model FOREIGN KEY (model_id) REFERENCES ml_models(model_id),
    CONSTRAINT fk_training_set FOREIGN KEY (set_id) REFERENCES training_sets(set_id)
);

-- Model real-time performance monitoring
CREATE TABLE model_performance (
    performance_id VARCHAR(50) PRIMARY KEY,
    model_id VARCHAR(50) NOT NULL,
    document_id VARCHAR(50),
    process_id VARCHAR(50),
    prediction_type VARCHAR(50) NOT NULL,
    input_hash VARCHAR(128), -- Hash of input for reproducibility
    prediction_output TEXT, -- JSON of model output
    confidence_score DECIMAL(5,4),
    execution_time_ms INT,
    memory_usage_mb DECIMAL(8,2),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    human_feedback VARCHAR(20), -- correct, incorrect, partially_correct
    feedback_notes TEXT,
    CONSTRAINT fk_performance_model FOREIGN KEY (model_id) REFERENCES ml_models(model_id),
    CONSTRAINT fk_performance_document FOREIGN KEY (document_id) REFERENCES original_copy(document_id),
    CONSTRAINT fk_performance_process FOREIGN KEY (process_id) REFERENCES process_control(process_id)
);

-- Training data table
CREATE TABLE training_data (
    training_id VARCHAR(50) PRIMARY KEY,
    data_type VARCHAR(50) NOT NULL,
    source_document_id VARCHAR(50),
    content TEXT NOT NULL,
    annotation TEXT,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_used_timestamp TIMESTAMP,
    usage_count INT DEFAULT 0,
    is_validated BOOLEAN DEFAULT FALSE,
    validation_score DECIMAL(5,2),
    validated_by VARCHAR(50),
    model_ids TEXT, -- Comma-separated list of models this data trains
    CONSTRAINT fk_training_document FOREIGN KEY (source_document_id) REFERENCES original_copy(document_id)
);

CREATE TABLE training_sets (
    set_id VARCHAR(50) PRIMARY KEY,
    set_name VARCHAR(100) NOT NULL,
    purpose VARCHAR(255) NOT NULL,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(50),
    size INT,
    description TEXT,
    version VARCHAR(20)
);

CREATE TABLE training_set_items (
    set_id VARCHAR(50) NOT NULL,
    training_id VARCHAR(50) NOT NULL,
    added_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (set_id, training_id),
    CONSTRAINT fk_set_items_set FOREIGN KEY (set_id) REFERENCES training_sets(set_id),
    CONSTRAINT fk_set_items_training FOREIGN KEY (training_id) REFERENCES training_data(training_id)
);

-- 7. Performance Metrics Database
-- Tracks system performance and processing metrics
CREATE TABLE performance_metrics (
    metric_id VARCHAR(50) PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_type VARCHAR(50) NOT NULL, -- throughput, latency, accuracy, etc.
    value DECIMAL(10,2) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(50), -- component name or service
    document_id VARCHAR(50),
    process_id VARCHAR(50),
    CONSTRAINT fk_metrics_document FOREIGN KEY (document_id) REFERENCES original_copy(document_id),
    CONSTRAINT fk_metrics_process FOREIGN KEY (process_id) REFERENCES process_control(process_id)
);

CREATE TABLE metric_thresholds (
    threshold_id VARCHAR(50) PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    warning_threshold DECIMAL(10,2),
    critical_threshold DECIMAL(10,2),
    direction VARCHAR(10) NOT NULL, -- "above" or "below"
    enabled BOOLEAN DEFAULT TRUE,
    notification_emails TEXT,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE metric_summaries (
    summary_id VARCHAR(50) PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    time_period VARCHAR(20) NOT NULL, -- daily, weekly, monthly
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    min_value DECIMAL(10,2),
    max_value DECIMAL(10,2),
    avg_value DECIMAL(10,2),
    median_value DECIMAL(10,2),
    p95_value DECIMAL(10,2),
    sample_count INT,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Cross-database relationships and views
CREATE VIEW document_processing_status AS
SELECT 
    o.document_id,
    o.file_name,
    m.document_type,
    m.patient_id,
    p.status AS process_status,
    p.current_step,
    p.completed_timestamp,
    v.version_number,
    v.validation_status,
    v.confidence_score
FROM 
    original_copy o
LEFT JOIN metadata m ON o.document_id = m.document_id
LEFT JOIN process_control p ON o.document_id = p.document_id
LEFT JOIN version_control v ON o.document_id = v.document_id AND v.is_current = TRUE;

-- Performance dashboard view
CREATE VIEW performance_dashboard AS
SELECT 
    DATE(pm.timestamp) AS metric_date,
    pm.metric_name,
    pm.metric_type,
    AVG(pm.value) AS avg_value,
    MIN(pm.value) AS min_value,
    MAX(pm.value) AS max_value,
    COUNT(*) AS sample_count,
    mt.warning_threshold,
    mt.critical_threshold
FROM 
    performance_metrics pm
LEFT JOIN metric_thresholds mt ON pm.metric_name = mt.metric_name
GROUP BY 
    DATE(pm.timestamp), pm.metric_name, pm.metric_type, mt.warning_threshold, mt.critical_threshold
ORDER BY 
    metric_date DESC, pm.metric_name;
    
-- =====================================================================
-- STORED PROCEDURES FOR FHIR HOUSE DATA MANAGEMENT
-- =====================================================================

-- 1. Document Registration Procedure
-- Registers a new document in the system
DELIMITER //

CREATE PROCEDURE RegisterNewDocument(
    IN p_document_id VARCHAR(50),
    IN p_content BLOB,
    IN p_file_name VARCHAR(255),
    IN p_file_type VARCHAR(50),
    IN p_file_size BIGINT,
    IN p_hash_value VARCHAR(128),
    IN p_source_system VARCHAR(100),
    IN p_title VARCHAR(255),
    IN p_author VARCHAR(100),
    IN p_created_date TIMESTAMP,
    IN p_document_type VARCHAR(50),
    IN p_patient_id VARCHAR(50),
    IN p_encounter_id VARCHAR(50),
    IN p_provider_id VARCHAR(50),
    IN p_organization_id VARCHAR(50),
    IN p_keywords TEXT,
    IN p_language VARCHAR(20)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        -- Log error
        INSERT INTO performance_metrics(metric_id, metric_name, metric_type, value, unit, source, document_id)
        VALUES(UUID(), 'Document Registration Error', 'error', 1, 'count', 'RegisterNewDocument', p_document_id);
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error registering new document';
    END;
    
    START TRANSACTION;
    
    -- Insert into original_copy
    INSERT INTO original_copy(document_id, content, file_name, file_type, file_size, hash_value, source_system)
    VALUES(p_document_id, p_content, p_file_name, p_file_type, p_file_size, p_hash_value, p_source_system);
    
    -- Insert into metadata
    INSERT INTO metadata(metadata_id, document_id, title, author, created_date, document_type, 
                        patient_id, encounter_id, provider_id, organization_id, keywords, language)
    VALUES(UUID(), p_document_id, p_title, p_author, p_created_date, p_document_type,
          p_patient_id, p_encounter_id, p_provider_id, p_organization_id, p_keywords, p_language);
    
    -- Create initial process control entry
    INSERT INTO process_control(process_id, process_type, status, document_id, current_step)
    VALUES(UUID(), 'document_processing', 'queued', p_document_id, 'classification');
    
    COMMIT;
    
    -- Record successful registration
    INSERT INTO performance_metrics(metric_id, metric_name, metric_type, value, unit, source, document_id)
    VALUES(UUID(), 'Document Registration', 'throughput', 1, 'count', 'RegisterNewDocument', p_document_id);
END //

DELIMITER ;

-- 2. Update Document Processing Status
-- Updates the status of a document's processing
DELIMITER //

CREATE PROCEDURE UpdateProcessingStatus(
    IN p_process_id VARCHAR(50),
    IN p_status VARCHAR(20),
    IN p_current_step VARCHAR(50),
    IN p_error_message TEXT
)
BEGIN
    DECLARE v_document_id VARCHAR(50);
    DECLARE v_previous_status VARCHAR(20);
    
    -- Get document ID and previous status
    SELECT document_id, status INTO v_document_id, v_previous_status
    FROM process_control
    WHERE process_id = p_process_id;
    
    -- Update process control
    UPDATE process_control
    SET 
        status = p_status,
        current_step = p_current_step,
        error_message = CASE WHEN p_status = 'error' THEN p_error_message ELSE error_message END,
        completed_timestamp = CASE WHEN p_status IN ('completed', 'failed') THEN CURRENT_TIMESTAMP ELSE NULL END,
        started_timestamp = CASE WHEN p_status = 'processing' AND v_previous_status = 'queued' THEN CURRENT_TIMESTAMP ELSE started_timestamp END,
        retry_count = CASE WHEN p_status = 'retry' THEN retry_count + 1 ELSE retry_count END
    WHERE process_id = p_process_id;
    
    -- Insert step record if moving to a new step
    IF p_current_step IS NOT NULL AND p_current_step != '' THEN
        INSERT INTO process_steps(step_id, process_id, step_name, step_order, status, started_timestamp)
        VALUES(UUID(), p_process_id, p_current_step, 
              (SELECT COUNT(*) FROM process_steps WHERE process_id = p_process_id) + 1, 
              'started', CURRENT_TIMESTAMP);
    END IF;
    
    -- Record metric for status change
    INSERT INTO performance_metrics(metric_id, metric_name, metric_type, value, unit, source, document_id, process_id)
    VALUES(UUID(), CONCAT('Status Change to ', p_status), 'state_change', 1, 'count', 'UpdateProcessingStatus', v_document_id, p_process_id);
END //

DELIMITER ;

-- 3. Create Document Version
-- Creates a new version of a document
DELIMITER //

CREATE PROCEDURE CreateDocumentVersion(
    IN p_document_id VARCHAR(50),
    IN p_content BLOB,
    IN p_created_by VARCHAR(50),
    IN p_change_summary TEXT,
    IN p_validation_status VARCHAR(20),
    IN p_confidence_score DECIMAL(5,2)
)
BEGIN
    DECLARE v_next_version INT;
    DECLARE v_version_id VARCHAR(50);
    
    -- Calculate next version number
    SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
    FROM version_control
    WHERE document_id = p_document_id;
    
    -- Set all current versions to not current
    UPDATE version_control
    SET is_current = FALSE
    WHERE document_id = p_document_id AND is_current = TRUE;
    
    -- Create new version
    SET v_version_id = UUID();
    INSERT INTO version_control(
        version_id, document_id, version_number, content, created_by, 
        change_summary, validation_status, confidence_score, is_current
    )
    VALUES(
        v_version_id, p_document_id, v_next_version, p_content, p_created_by,
        p_change_summary, p_validation_status, p_confidence_score, TRUE
    );
    
    -- Record metric
    INSERT INTO performance_metrics(metric_id, metric_name, metric_type, value, unit, source, document_id)
    VALUES(UUID(), 'Version Created', 'state_change', v_next_version, 'version', 'CreateDocumentVersion', p_document_id);
    
    -- Return the new version ID
    SELECT v_version_id AS new_version_id, v_next_version AS version_number;
END //

DELIMITER ;

-- 4. Add Training Data
-- Adds data to the training database
DELIMITER //

CREATE PROCEDURE AddTrainingData(
    IN p_data_type VARCHAR(50),
    IN p_source_document_id VARCHAR(50),
    IN p_content TEXT,
    IN p_annotation TEXT,
    IN p_set_name VARCHAR(100),
    IN p_set_purpose VARCHAR(255),
    IN p_created_by VARCHAR(50)
)
BEGIN
    DECLARE v_training_id VARCHAR(50);
    DECLARE v_set_id VARCHAR(50);
    DECLARE v_set_exists INT;
    
    -- Generate a new training ID
    SET v_training_id = UUID();
    
    -- Insert the training data
    INSERT INTO training_data(
        training_id, data_type, source_document_id, content, 
        annotation, created_by
    )
    VALUES(
        v_training_id, p_data_type, p_source_document_id, p_content,
        p_annotation, p_created_by
    );
    
    -- Check if the set exists
    SELECT COUNT(*), set_id INTO v_set_exists, v_set_id
    FROM training_sets
    WHERE set_name = p_set_name
    GROUP BY set_id;
    
    -- Create the set if it doesn't exist
    IF v_set_exists = 0 OR v_set_exists IS NULL THEN
        SET v_set_id = UUID();
        INSERT INTO training_sets(
            set_id, set_name, purpose, created_by, description, version
        )
        VALUES(
            v_set_id, p_set_name, p_set_purpose, p_created_by, 
            CONCAT('Created for ', p_data_type, ' training'), '1.0'
        );
    END IF;
    
    -- Add the training data to the set
    INSERT INTO training_set_items(set_id, training_id)
    VALUES(v_set_id, v_training_id);
    
    -- Update the set size
    UPDATE training_sets
    SET size = (SELECT COUNT(*) FROM training_set_items WHERE set_id = v_set_id)
    WHERE set_id = v_set_id;
    
    -- Return the IDs
    SELECT v_training_id AS training_id, v_set_id AS set_id;
END //

DELIMITER ;

-- 5. Process Low Confidence Documents
-- Identifies and flags documents that need human review
DELIMITER //

CREATE PROCEDURE ProcessLowConfidenceDocuments(
    IN p_threshold DECIMAL(5,2)
)
BEGIN
    DECLARE v_document_id VARCHAR(50);
    DECLARE v_version_id VARCHAR(50);
    DECLARE v_confidence_score DECIMAL(5,2);
    DECLARE done INT DEFAULT FALSE;
    
    -- Cursor for low confidence documents
    DECLARE low_confidence_cursor CURSOR FOR
        SELECT vc.document_id, vc.version_id, vc.confidence_score
        FROM version_control vc
        JOIN process_control pc ON vc.document_id = pc.document_id
        WHERE vc.is_current = TRUE 
          AND vc.confidence_score < p_threshold
          AND pc.status != 'human_review_required';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN low_confidence_cursor;
    
    read_loop: LOOP
        FETCH low_confidence_cursor INTO v_document_id, v_version_id, v_confidence_score;
        
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Update process control to require human review
        UPDATE process_control
        SET status = 'human_review_required',
            current_step = 'human_validation',
            assigned_to = NULL
        WHERE document_id = v_document_id;
        
        -- Add a process step
        INSERT INTO process_steps(
            step_id, process_id, step_name, step_order, status, started_timestamp,
            input_parameters
        )
        SELECT 
            UUID(), process_id, 'human_validation',
            (SELECT COUNT(*) FROM process_steps WHERE process_id = pc.process_id) + 1,
            'pending', CURRENT_TIMESTAMP,
            CONCAT('{"confidence_score":', v_confidence_score, ', "threshold":', p_threshold, '}')
        FROM process_control pc
        WHERE pc.document_id = v_document_id;
        
        -- Record metric
        INSERT INTO performance_metrics(
            metric_id, metric_name, metric_type, value, unit, source, document_id
        )
        VALUES(
            UUID(), 'Low Confidence Document', 'quality', v_confidence_score, 'score',
            'ProcessLowConfidenceDocuments', v_document_id
        );
    END LOOP;
    
    CLOSE low_confidence_cursor;
    
    -- Return count of processed documents
    SELECT COUNT(*) AS processed_count
    FROM process_control
    WHERE status = 'human_review_required' 
      AND current_step = 'human_validation';
END //

DELIMITER ;

-- 6. Generate Performance Report
-- Creates a comprehensive performance report for a date range
DELIMITER //

CREATE PROCEDURE GeneratePerformanceReport(
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    -- Processing throughput
    SELECT 
        DATE(pc.completed_timestamp) AS processing_date,
        COUNT(*) AS documents_processed,
        AVG(TIMESTAMPDIFF(SECOND, pc.started_timestamp, pc.completed_timestamp)) AS avg_processing_time_seconds
    FROM process_control pc
    WHERE pc.completed_timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(pc.completed_timestamp)
    ORDER BY processing_date;
    
    -- Quality metrics
    SELECT 
        DATE(vc.created_timestamp) AS version_date,
        COUNT(*) AS versions_created,
        AVG(vc.confidence_score) AS avg_confidence,
        COUNT(CASE WHEN vc.confidence_score < 0.7 THEN 1 END) AS low_confidence_count
    FROM version_control vc
    WHERE vc.created_timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(vc.created_timestamp)
    ORDER BY version_date;
    
    -- Error rates
    SELECT 
        DATE(pc.started_timestamp) AS process_date,
        COUNT(*) AS total_processes,
        COUNT(CASE WHEN pc.status = 'failed' THEN 1 END) AS failed_count,
        COUNT(CASE WHEN pc.status = 'error' THEN 1 END) AS error_count,
        COUNT(CASE WHEN pc.retry_count > 0 THEN 1 END) AS retry_count,
        (COUNT(CASE WHEN pc.status IN ('failed', 'error') THEN 1 END) / COUNT(*)) * 100 AS error_percent
    FROM process_control pc
    WHERE pc.started_timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(pc.started_timestamp)
    ORDER BY process_date;
    
    -- Processing pipeline performance by step
    SELECT 
        ps.step_name,
        COUNT(*) AS execution_count,
        AVG(ps.execution_time_ms) AS avg_execution_time_ms,
        MAX(ps.execution_time_ms) AS max_execution_time_ms,
        COUNT(CASE WHEN ps.status = 'error' THEN 1 END) AS error_count,
        (COUNT(CASE WHEN ps.status = 'error' THEN 1 END) / COUNT(*)) * 100 AS error_rate
    FROM process_steps ps
    JOIN process_control pc ON ps.process_id = pc.process_id
    WHERE ps.completed_timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY ps.step_name
    ORDER BY avg_execution_time_ms DESC;
    
    -- System performance metrics
    SELECT 
        pm.metric_name,
        pm.metric_type,
        AVG(pm.value) AS avg_value,
        MIN(pm.value) AS min_value,
        MAX(pm.value) AS max_value,
        STDDEV(pm.value) AS std_dev
    FROM performance_metrics pm
    WHERE pm.timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY pm.metric_name, pm.metric_type
    ORDER BY pm.metric_type, pm.metric_name;
END //

DELIMITER ;

-- 7. Backup Management Procedure
-- Initiates database backups according to schedule
DELIMITER //

CREATE PROCEDURE ExecuteScheduledBackups()
BEGIN
    DECLARE v_schedule_id VARCHAR(50);
    DECLARE v_backup_type VARCHAR(20);
    DECLARE v_retention_period INT;
    DECLARE v_backup_id VARCHAR(50);
    DECLARE v_location VARCHAR(255);
    DECLARE done INT DEFAULT FALSE;
    
    -- Cursor for due backups
    DECLARE backup_cursor CURSOR FOR
        SELECT schedule_id, backup_type, retention_period
        FROM backup_schedule
        WHERE next_execution <= CURRENT_TIMESTAMP AND status = 'active';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN backup_cursor;
    
    read_loop: LOOP
        FETCH backup_cursor INTO v_schedule_id, v_backup_type, v_retention_period;
        
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Generate backup ID and location
        SET v_backup_id = UUID();
        SET v_location = CONCAT('/backups/', v_backup_type, '/', DATE_FORMAT(CURRENT_TIMESTAMP, '%Y%m%d_%H%i%s'));
        
        -- Start backup
        INSERT INTO backup_log(
            backup_id, schedule_id, start_time, location, status
        )
        VALUES(
            v_backup_id, v_schedule_id, CURRENT_TIMESTAMP, v_location, 'in_progress'
        );
        
        -- Here you would implement the actual backup logic
        -- For different databases and backup types
        -- This is placeholder for the actual backup implementation
        
        -- For demo purposes, we'll just update the status to completed
        -- In a real system, you would perform the backup and update with real values
        UPDATE backup_log
        SET 
            end_time = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 5 MINUTE),
            size_bytes = FLOOR(RAND() * 1000000000),
            status = 'completed'
        WHERE backup_id = v_backup_id;
        
        -- Update the schedule for next execution
        UPDATE backup_schedule
        SET 
            last_execution = CURRENT_TIMESTAMP,
            next_execution = CASE 
                WHEN frequency = 'daily' THEN DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 1 DAY)
                WHEN frequency = 'weekly' THEN DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 1 WEEK)
                WHEN frequency = 'monthly' THEN DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 1 MONTH)
                ELSE DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 1 DAY)
            END
        WHERE schedule_id = v_schedule_id;
        
        -- Delete old backups that exceed retention period
        DELETE FROM backup_log
        WHERE schedule_id = v_schedule_id
          AND status = 'completed'
          AND start_time < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL v_retention_period DAY);
    END LOOP;
    
    CLOSE backup_cursor;
END //

DELIMITER ;

-- 8. Add Document to Training Data
-- Adds a processed document to the training dataset
DELIMITER //

CREATE PROCEDURE AddDocumentToTrainingData(
    IN p_document_id VARCHAR(50),
    IN p_created_by VARCHAR(50),
    IN p_training_type VARCHAR(50),
    IN p_set_name VARCHAR(100)
)
BEGIN
    DECLARE v_content TEXT;
    DECLARE v_metadata_json TEXT;
    DECLARE v_training_id VARCHAR(50);
    
    -- Get document content and metadata
    SELECT 
        vc.content,
        CONCAT('{',
            '"document_id":"', oc.document_id, '",',
            '"document_type":"', m.document_type, '",',
            '"patient_id":"', m.patient_id, '",',
            '"version_number":', vc.version_number, ',',
            '"confidence_score":', vc.confidence_score, ',',
            '"validation_status":"', vc.validation_status, '"',
        '}')
    INTO v_content, v_metadata_json
    FROM version_control vc
    JOIN original_copy oc ON vc.document_id = oc.document_id
    JOIN metadata m ON oc.document_id = m.document_id
    WHERE vc.document_id = p_document_id AND vc.is_current = TRUE;
    
    -- Add to training data
    CALL AddTrainingData(
        p_training_type,
        p_document_id,
        v_content,
        v_metadata_json,
        p_set_name,
        CONCAT('Training data for ', p_training_type),
        p_created_by
    );
    
    -- Update document processing status to mark as used for training
    UPDATE process_control
    SET status = 'used_for_training'
    WHERE document_id = p_document_id AND status = 'completed';
END //

DELIMITER ;

-- 9. Reset Failed Process
-- Resets a failed process for retry
DELIMITER //

CREATE PROCEDURE ResetFailedProcess(
    IN p_process_id VARCHAR(50)
)
BEGIN
    DECLARE v_max_retries INT;
    DECLARE v_current_retries INT;
    DECLARE v_last_step VARCHAR(50);
    
    -- Get current retry info
    SELECT max_retries, retry_count, current_step
    INTO v_max_retries, v_current_retries, v_last_step
    FROM process_control
    WHERE process_id = p_process_id;
    
    -- Check if we can retry
    IF v_current_retries < v_max_retries THEN
        -- Reset process to retry
        UPDATE process_control
        SET 
            status = 'retry',
            retry_count = v_current_retries + 1,
            error_message = CONCAT(error_message, ' | Retry #', v_current_retries + 1, ' on ', CURRENT_TIMESTAMP)
        WHERE process_id = p_process_id;
        
        -- Add retry entry to steps
        INSERT INTO process_steps(
            step_id, process_id, step_name, step_order, status, started_timestamp
        )
        VALUES(
            UUID(), p_process_id, CONCAT('retry_', v_last_step),
            (SELECT COUNT(*) FROM process_steps WHERE process_id = p_process_id) + 1,
            'started', CURRENT_TIMESTAMP
        );
        
        -- Record metric
        INSERT INTO performance_metrics(
            metric_id, metric_name, metric_type, value, unit, source, process_id
        )
        VALUES(
            UUID(), 'Process Retry', 'reliability', v_current_retries + 1, 'count',
            'ResetFailedProcess', p_process_id
        );
        
        SELECT 'Process reset for retry' AS result;
    ELSE
        SELECT 'Max retries exceeded' AS result;
    END IF;
END //

DELIMITER ;

-- 10. Assign Human Review
-- Assigns documents requiring human review to personnel
DELIMITER //

CREATE PROCEDURE AssignHumanReview(
    IN p_assigned_to VARCHAR(50),
    IN p_batch_size INT
)
BEGIN
    -- Update process control for a batch of unassigned documents
    UPDATE process_control
    SET 
        assigned_to = p_assigned_to,
        status = 'human_review_in_progress'
    WHERE status = 'human_review_required'
      AND assigned_to IS NULL
    LIMIT p_batch_size;
    
    -- Report assigned count
    SELECT COUNT(*) AS assigned_count
    FROM process_control
    WHERE assigned_to = p_assigned_to
      AND status = 'human_review_in_progress';
END //

DELIMITER ;

-- 11. Register and Deploy ML Model
-- Registers a new ML model and optionally deploys it
DELIMITER //

CREATE PROCEDURE RegisterMLModel(
    IN p_model_id VARCHAR(50),
    IN p_model_name VARCHAR(100),
    IN p_model_type VARCHAR(50),
    IN p_version VARCHAR(20),
    IN p_description TEXT,
    IN p_binary_data LONGBLOB,
    IN p_model_format VARCHAR(50),
    IN p_framework VARCHAR(50),
    IN p_parameters TEXT,
    IN p_hash_value VARCHAR(128),
    IN p_created_by VARCHAR(50),
    IN p_training_duration_seconds INT,
    IN p_training_config TEXT,
    IN p_evaluation_metrics TEXT,
    IN p_accuracy DECIMAL(5,4),
    IN p_f1_score DECIMAL(5,4),
    IN p_precision_score DECIMAL(5,4),
    IN p_recall_score DECIMAL(5,4),
    IN p_parent_model_id VARCHAR(50),
    IN p_deploy_to_production BOOLEAN,
    IN p_training_set_ids TEXT -- Comma-separated list of training set IDs
)
BEGIN
    DECLARE v_size_bytes BIGINT;
    DECLARE v_deploy_id VARCHAR(50);
    DECLARE v_dependency VARCHAR(100);
    DECLARE v_dep_version VARCHAR(50);
    DECLARE v_training_set_id VARCHAR(50);
    DECLARE v_dependency_str TEXT;
    DECLARE v_pos INT;
    DECLARE v_next_pos INT;
    DECLARE v_end_loop BOOLEAN DEFAULT FALSE;
    
    -- Calculate model size
    SET v_size_bytes = LENGTH(p_binary_data);
    
    -- Begin transaction
    START TRANSACTION;
    
    -- Insert the model
    INSERT INTO ml_models(
        model_id, model_name, model_type, version, description, 
        binary_data, model_format, framework, parameters, size_bytes,
        hash_value, created_by, last_trained_timestamp, training_duration_seconds,
        training_config, evaluation_metrics, accuracy, f1_score, 
        precision_score, recall_score, parent_model_id, 
        is_active, is_production
    )
    VALUES(
        p_model_id, p_model_name, p_model_type, p_version, p_description,
        p_binary_data, p_model_format, p_framework, p_parameters, v_size_bytes,
        p_hash_value, p_created_by, CURRENT_TIMESTAMP, p_training_duration_seconds,
        p_training_config, p_evaluation_metrics, p_accuracy, p_f1_score,
        p_precision_score, p_recall_score, p_parent_model_id,
        TRUE, p_deploy_to_production
    );
    
    -- If making this model active, deactivate other models of the same type
    IF p_deploy_to_production THEN
        UPDATE ml_models
        SET 
            is_production = FALSE,
            is_active = CASE WHEN model_id = p_model_id THEN TRUE ELSE FALSE END
        WHERE model_type = p_model_type AND model_id != p_model_id;
        
        -- Create deployment record
        SET v_deploy_id = UUID();
        INSERT INTO model_deployments(
            deployment_id, model_id, environment, deployed_by,
            status, config_parameters, deployment_notes
        )
        VALUES(
            v_deploy_id, p_model_id, 'production', p_created_by,
            'success', '{"automatic": true}', 'Auto-deployed during registration'
        );
        
        -- Update last deployed timestamp
        UPDATE ml_models
        SET last_deployed_timestamp = CURRENT_TIMESTAMP
        WHERE model_id = p_model_id;
    END IF;
    
    -- Process dependencies if provided
    IF p_parameters IS NOT NULL AND JSON_EXTRACT(p_parameters, '$.dependencies') IS NOT NULL THEN
        SET v_dependency_str = JSON_EXTRACT(p_parameters, '$.dependencies');
        
        -- Parse JSON array of dependencies
        SET v_pos = 1;
        WHILE NOT v_end_loop DO
            -- Extract dependency name and version
            SET v_dependency = JSON_UNQUOTE(JSON_EXTRACT(v_dependency_str, CONCAT('$[', v_pos-1, '].name')));
            SET v_dep_version = JSON_UNQUOTE(JSON_EXTRACT(v_dependency_str, CONCAT('$[', v_pos-1, '].version')));
            
            -- If no more dependencies, exit loop
            IF v_dependency IS NULL THEN
                SET v_end_loop = TRUE;
            ELSE
                -- Insert dependency
                INSERT INTO model_dependencies(
                    dependency_id, model_id, library_name, version
                )
                VALUES(
                    UUID(), p_model_id, v_dependency, v_dep_version
                );
                
                SET v_pos = v_pos + 1;
            END IF;
        END WHILE;
    END IF;
    
    -- Process training sets
    IF p_training_set_ids IS NOT NULL AND p_training_set_ids != '' THEN
        -- Split comma-separated list and insert
        SET v_pos = 1;
        SET v_end_loop = FALSE;
        
        WHILE NOT v_end_loop DO
            -- Find next comma
            SET v_next_pos = LOCATE(',', p_training_set_ids, v_pos);
            
            -- If no more commas, process last ID
            IF v_next_pos = 0 THEN
                SET v_training_set_id = SUBSTRING(p_training_set_ids, v_pos);
                SET v_end_loop = TRUE;
            ELSE
                SET v_training_set_id = SUBSTRING(p_training_set_ids, v_pos, v_next_pos - v_pos);
                SET v_pos = v_next_pos + 1;
            END IF;
            
            -- Insert if we have a valid ID
            IF v_training_set_id IS NOT NULL AND v_training_set_id != '' THEN
                INSERT INTO model_training_sets(
                    model_id, set_id
                )
                VALUES(
                    p_model_id, TRIM(v_training_set_id)
                );
            END IF;
        END WHILE;
    END IF;
    
    COMMIT;
    
    -- Return new model info
    SELECT 
        model_id, 
        model_name, 
        version, 
        CASE WHEN p_deploy_to_production THEN 'Deployed to production' ELSE 'Registered only' END AS status,
        created_timestamp
    FROM ml_models
    WHERE model_id = p_model_id;
END //

DELIMITER ;

-- 12. Evaluate Model Performance
-- Evaluates model performance over time
DELIMITER //

CREATE PROCEDURE EvaluateModelPerformance(
    IN p_model_id VARCHAR(50),
    IN p_start_date TIMESTAMP,
    IN p_end_date TIMESTAMP
)
BEGIN
    -- Get model details
    SELECT 
        model_name,
        model_type,
        version,
        framework,
        accuracy AS training_accuracy,
        f1_score AS training_f1,
        precision_score AS training_precision,
        recall_score AS training_recall,
        created_timestamp,
        last_deployed_timestamp
    FROM ml_models
    WHERE model_id = p_model_id;
    
    -- Get performance metrics over time
    SELECT 
        DATE(timestamp) AS performance_date,
        COUNT(*) AS predictions,
        AVG(confidence_score) AS avg_confidence,
        AVG(execution_time_ms) AS avg_execution_time_ms,
        MAX(execution_time_ms) AS max_execution_time_ms,
        COUNT(CASE WHEN human_feedback = 'correct' THEN 1 END) AS correct_predictions,
        COUNT(CASE WHEN human_feedback = 'incorrect' THEN 1 END) AS incorrect_predictions,
        COUNT(CASE WHEN human_feedback = 'partially_correct' THEN 1 END) AS partially_correct,
        COUNT(CASE WHEN human_feedback IS NOT NULL THEN 1 END) AS total_feedback,
        CASE 
            WHEN COUNT(CASE WHEN human_feedback IS NOT NULL THEN 1 END) > 0 
            THEN (COUNT(CASE WHEN human_feedback = 'correct' THEN 1 END) / 
                  COUNT(CASE WHEN human_feedback IS NOT NULL THEN 1 END)) * 100
            ELSE NULL
        END AS accuracy_percentage
    FROM model_performance
    WHERE model_id = p_model_id
      AND timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(timestamp)
    ORDER BY performance_date;
    
    -- Get performance by document type
    SELECT 
        m.document_type,
        COUNT(*) AS predictions,
        AVG(mp.confidence_score) AS avg_confidence,
        COUNT(CASE WHEN mp.human_feedback = 'correct' THEN 1 END) AS correct_predictions,
        COUNT(CASE WHEN mp.human_feedback = 'incorrect' THEN 1 END) AS incorrect_predictions,
        CASE 
            WHEN COUNT(CASE WHEN mp.human_feedback IS NOT NULL THEN 1 END) > 0 
            THEN (COUNT(CASE WHEN mp.human_feedback = 'correct' THEN 1 END) / 
                  COUNT(CASE WHEN mp.human_feedback IS NOT NULL THEN 1 END)) * 100
            ELSE NULL
        END AS accuracy_percentage
    FROM model_performance mp
    JOIN metadata m ON mp.document_id = m.document_id
    WHERE mp.model_id = p_model_id
      AND mp.timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY m.document_type
    ORDER BY predictions DESC;
    
    -- Get low confidence predictions
    SELECT 
        mp.document_id,
        m.document_type,
        mp.prediction_type,
        mp.confidence_score,
        mp.human_feedback,
        mp.timestamp
    FROM model_performance mp
    JOIN metadata m ON mp.document_id = m.document_id
    WHERE mp.model_id = p_model_id
      AND mp.timestamp BETWEEN p_start_date AND p_end_date
      AND mp.confidence_score < 0.7
    ORDER BY mp.confidence_score ASC
    LIMIT 100;
END //

DELIMITER ;