function graphEditorApp()
% GRAPHEDITORAPP
% Standalone app to create a MATLAB graph on top of an image
    %% App state
    nodePositions = [];
    nodeNames = {};  % Store node names
    edges = [];
    edgeWeights = [];  % Store edge weights
    selectedNode = [];
    imgData = [];
    ax = [];
    imgHandle = [];
    nodeListBox = [];
    edgeListBox = [];
    nodeHandles = [];  % Store handles to node markers
    
    %% UI
    fig = uifigure('Name','Graph Editor',...
        'Position',[100 100 1300 600]);
    ax = uiaxes(fig,...
        'Position',[20 20 650 560]);
    axis(ax,'ij');
    hold(ax,'on');
    
    % Buttons
    uibutton(fig,'Text','Load Image',...
        'Position',[700 520 160 30],...
        'ButtonPushedFcn',@loadImage);
    uibutton(fig,'Text','Save Graph',...
        'Position',[700 470 160 30],...
        'ButtonPushedFcn',@saveGraph);
    uibutton(fig,'Text','Load Graph',...
        'Position',[700 420 160 30],...
        'ButtonPushedFcn',@loadGraph);
    uibutton(fig,'Text','Clear',...
        'Position',[700 370 160 30],...
        'ButtonPushedFcn',@clearAll);
    
    % Mode selector
    modeLabel = uilabel(fig,'Text','Mode:',...
        'Position',[700 320 160 20]);
    modeSwitch = uiswitch(fig,'slider',...
        'Position',[700 280 45 20],...
        'Items',{'Add Nodes','Add Edges'},...
        'Value','Add Nodes',...
        'ValueChangedFcn',@modeChanged);
    
    % Status label
    statusLabel = uilabel(fig,'Text','Load an image to begin',...
        'Position',[700 240 160 40],...
        'FontColor',[0.5 0.5 0.5],...
        'WordWrap','on');
    
    % Node list section
    nodeListLabel = uilabel(fig,'Text','Nodes:',...
        'Position',[880 560 200 20],...
        'FontWeight','bold');
    
    nodeListBox = uilistbox(fig,...
        'Position',[880 340 200 210],...
        'Items',{},...
        'ValueChangedFcn',@nodeSelected);
    
    % Node name edit field
    nodeNameLabel = uilabel(fig,'Text','Node Name:',...
        'Position',[880 300 100 20]);
    
    nodeNameField = uieditfield(fig,'text',...
        'Position',[880 270 200 30],...
        'ValueChangedFcn',@updateNodeName,...
        'Enable','off');
    
    % Delete node button
    uibutton(fig,'Text','Delete Node',...
        'Position',[880 230 200 30],...
        'ButtonPushedFcn',@deleteNode);
    
    % Edge list section
    edgeListLabel = uilabel(fig,'Text','Edges:',...
        'Position',[1100 560 180 20],...
        'FontWeight','bold');
    
    edgeListBox = uilistbox(fig,...
        'Position',[1100 340 180 210],...
        'Items',{},...
        'ValueChangedFcn',@edgeSelected);
    
    % Edge weight edit field
    edgeWeightLabel = uilabel(fig,'Text','Edge Weight:',...
        'Position',[1100 300 100 20]);
    
    edgeWeightField = uieditfield(fig,'numeric',...
        'Position',[1100 270 180 30],...
        'ValueChangedFcn',@updateEdgeWeight,...
        'Enable','off',...
        'Value',1,...
        'Limits',[0 Inf]);
    
    % Delete edge button
    uibutton(fig,'Text','Delete Edge',...
        'Position',[1100 230 180 30],...
        'ButtonPushedFcn',@deleteEdge);
    
    % Show weights checkbox
    showWeightsCheck = uicheckbox(fig,...
        'Position',[1100 190 180 30],...
        'Text','Show weights on graph',...
        'ValueChangedFcn',@(~,~)redrawGraph());
    
    %% ---------------- Callbacks ----------------
    function loadImage(~,~)
        [file,path] = uigetfile({'*.png;*.jpg;*.jpeg;*.pdf','Image Files (*.png,*.jpg,*.jpeg,*.pdf)'},'Load Image');
        if isequal(file,0); return; end
        
        fullPath = fullfile(path,file);
        [~,~,ext] = fileparts(file);
        
        % Handle PDF files
        if strcmpi(ext,'.pdf')
            try
                imgData = readPDF(fullPath);
            catch ME
                uialert(fig,['Error loading PDF: ' ME.message],'Load Error');
                return;
            end
        else
            imgData = imread(fullPath);
        end
        
        cla(ax);
        imgHandle = imagesc(ax, imgData);
        axis(ax,'image','ij');
        hold(ax,'on');
        ax.Toolbar.Visible = 'off';
        
        % Set up click callback on the image
        set(imgHandle, 'ButtonDownFcn', @imageClicked);
        
        redrawGraph();
        updateStatus();
        fprintf('Image loaded successfully!\n');
    end
    
    function img = readPDF(pdfPath)
        try
            imgs = importPDFImages(pdfPath, 1);
            img = imgs{1};
        catch
            try
                img = imread(pdfPath, 1);
            catch
                error('Unable to read PDF. Please ensure the PDF is not encrypted and MATLAB has PDF support.');
            end
        end
    end
    
    function modeChanged(~,~)
        selectedNode = [];
        updateStatus();
        redrawGraph();
    end
    
    function updateStatus()
        if strcmp(modeSwitch.Value, 'Add Nodes')
            statusLabel.Text = 'Click on image to add nodes';
            statusLabel.FontColor = [0 0.5 0];
        else
            if isempty(selectedNode)
                statusLabel.Text = 'Click on a node to select it';
                statusLabel.FontColor = [0 0 0.8];
            else
                statusLabel.Text = sprintf('Node %d selected. Click another node to create edge', selectedNode);
                statusLabel.FontColor = [0.8 0 0];
            end
        end
    end
    
    function imageClicked(~,event)
        if isempty(imgData); return; end
        
        % Get click coordinates
        cp = event.IntersectionPoint(1:2);
        
        if strcmp(modeSwitch.Value, 'Add Nodes')
            % Node creation mode
            nodePositions(end+1,:) = cp;
            nodeNames{end+1} = sprintf('Node %d', size(nodePositions,1));
            fprintf('*** New node %d created at (%.1f, %.1f) ***\n', size(nodePositions,1), cp(1), cp(2));
            updateNodeList();
            redrawGraph();
        end
    end
    
    function nodeClicked(nodeIdx)
        % Called when a node marker is clicked
        fprintf('Node %d clicked\n', nodeIdx);
        
        if strcmp(modeSwitch.Value, 'Add Edges')
            if isempty(selectedNode)
                % First node selection
                selectedNode = nodeIdx;
                fprintf('*** Node %d selected ***\n', nodeIdx);
            else
                % Second node selection - create edge
                if selectedNode ~= nodeIdx
                    newEdge = sort([selectedNode nodeIdx]);
                    
                    % Check if edge already exists - handle empty edges array
                    edgeExists = false;
                    if ~isempty(edges)
                        edgeExists = ismember(newEdge, edges, 'rows');
                    end
                    
                    if ~edgeExists
                        edges = [edges; newEdge];  % Add new edge
                        edgeWeights = [edgeWeights; 1];  % Default weight = 1
                        fprintf('*** Edge created: %d - %d (weight=1) ***\n', selectedNode, nodeIdx);
                        updateEdgeList();
                    else
                        fprintf('Edge already exists\n');
                    end
                else
                    fprintf('Same node clicked - deselecting\n');
                end
                selectedNode = [];
            end
            updateStatus();
            redrawGraph();
        end
    end
    
    function updateNodeList()
        % Update the listbox with node names
        listItems = cell(size(nodeNames));
        for i = 1:length(nodeNames)
            if isempty(nodeNames{i})
                listItems{i} = sprintf('%d: Node %d', i, i);
            else
                listItems{i} = sprintf('%d: %s', i, nodeNames{i});
            end
        end
        nodeListBox.Items = listItems;
    end
    
    function updateEdgeList()
        % Update the listbox with edges
        if isempty(edges)
            edgeListBox.Items = {};
            return;
        end
        
        listItems = cell(size(edges,1),1);
        for i = 1:size(edges,1)
            n1 = edges(i,1);
            n2 = edges(i,2);
            
            % Get node names
            name1 = nodeNames{n1};
            name2 = nodeNames{n2};
            
            if isempty(name1); name1 = num2str(n1); end
            if isempty(name2); name2 = num2str(n2); end
            
            listItems{i} = sprintf('%d: %s - %s (w=%.2f)', i, name1, name2, edgeWeights(i));
        end
        edgeListBox.Items = listItems;
    end
    
    function nodeSelected(~,~)
        % When a node is selected in the list
        if isempty(nodeListBox.Value)
            nodeNameField.Enable = 'off';
            nodeNameField.Value = '';
            return;
        end
        
        % Extract node index from selection
        selectedStr = nodeListBox.Value;
        idx = str2double(regexp(selectedStr, '^\d+', 'match', 'once'));
        
        if ~isnan(idx) && idx > 0 && idx <= length(nodeNames)
            nodeNameField.Enable = 'on';
            nodeNameField.Value = nodeNames{idx};
            nodeNameField.UserData = idx;  % Store current node index
        end
    end
    
    function edgeSelected(~,~)
        % When an edge is selected in the list
        if isempty(edgeListBox.Value)
            edgeWeightField.Enable = 'off';
            edgeWeightField.Value = 1;
            return;
        end
        
        % Extract edge index from selection
        selectedStr = edgeListBox.Value;
        idx = str2double(regexp(selectedStr, '^\d+', 'match', 'once'));
        
        if ~isnan(idx) && idx > 0 && idx <= length(edgeWeights)
            edgeWeightField.Enable = 'on';
            edgeWeightField.Value = edgeWeights(idx);
            edgeWeightField.UserData = idx;  % Store current edge index
        end
    end
    
    function updateNodeName(~,~)
        % Update the name of the currently selected node
        idx = nodeNameField.UserData;
        if ~isempty(idx) && idx > 0 && idx <= length(nodeNames)
            nodeNames{idx} = nodeNameField.Value;
            updateNodeList();
            updateEdgeList();  % Edge list shows node names
            redrawGraph();
            fprintf('Node %d renamed to: %s\n', idx, nodeNames{idx});
        end
    end
    
    function updateEdgeWeight(~,~)
        % Update the weight of the currently selected edge
        idx = edgeWeightField.UserData;
        if ~isempty(idx) && idx > 0 && idx <= length(edgeWeights)
            edgeWeights(idx) = edgeWeightField.Value;
            updateEdgeList();
            redrawGraph();
            fprintf('Edge %d weight set to: %.2f\n', idx, edgeWeights(idx));
        end
    end
    
    function deleteNode(~,~)
        if isempty(nodeListBox.Value)
            uialert(fig, 'Please select a node to delete', 'No Selection');
            return;
        end
        
        % Extract node index
        selectedStr = nodeListBox.Value;
        idx = str2double(regexp(selectedStr, '^\d+', 'match', 'once'));
        
        if isnan(idx) || idx < 1 || idx > length(nodeNames)
            return;
        end
        
        % Remove node
        nodePositions(idx,:) = [];
        nodeNames(idx) = [];
        
        % Update edges - remove edges involving this node
        if ~isempty(edges)
            edgesToRemove = any(edges == idx, 2);
            edges(edgesToRemove,:) = [];
            edgeWeights(edgesToRemove) = [];
            
            % Renumber edges with higher indices
            edges(edges > idx) = edges(edges > idx) - 1;
        end
        
        % Clear selection
        selectedNode = [];
        nodeNameField.Value = '';
        nodeNameField.Enable = 'off';
        
        updateNodeList();
        updateEdgeList();
        updateStatus();
        redrawGraph();
        fprintf('Node %d deleted\n', idx);
    end
    
    function deleteEdge(~,~)
        if isempty(edgeListBox.Value)
            uialert(fig, 'Please select an edge to delete', 'No Selection');
            return;
        end
        
        % Extract edge index
        selectedStr = edgeListBox.Value;
        idx = str2double(regexp(selectedStr, '^\d+', 'match', 'once'));
        
        if isnan(idx) || idx < 1 || idx > size(edges,1)
            return;
        end
        
        % Remove edge
        fprintf('Edge %d deleted (%d-%d)\n', idx, edges(idx,1), edges(idx,2));
        edges(idx,:) = [];
        edgeWeights(idx) = [];
        
        % Clear selection
        edgeWeightField.Value = 1;
        edgeWeightField.Enable = 'off';
        
        updateEdgeList();
        redrawGraph();
    end
    
    function redrawGraph()
        % Delete existing plot objects (but not the image)
        delete(findobj(ax,'Type','line'));
        delete(findobj(ax,'Type','text'));
        delete(findobj(ax,'Tag','nodeMarker'));
        nodeHandles = [];
        
        % Draw edges
        for i = 1:size(edges,1)
            p1 = nodePositions(edges(i,1),:);
            p2 = nodePositions(edges(i,2),:);
            
            % Draw edge line
            plot(ax,[p1(1) p2(1)],[p1(2) p2(2)],'g-','LineWidth',2);
            
            % Show weight if checkbox is checked
            if showWeightsCheck.Value
                midPoint = [(p1(1)+p2(1))/2, (p1(2)+p2(2))/2];
                text(ax, midPoint(1), midPoint(2), sprintf('%.2f', edgeWeights(i)),...
                    'Color','w','FontWeight','bold','FontSize',9,...
                    'BackgroundColor',[0 0.5 0 0.7],'EdgeColor','none',...
                    'HorizontalAlignment','center','PickableParts','none');
            end
        end
        
        % Draw nodes with clickable markers
        for i = 1:size(nodePositions,1)
            % Draw larger invisible clickable area
            h = plot(ax,nodePositions(i,1),nodePositions(i,2),...
                'ro','MarkerSize',20,'MarkerFaceColor','r',...
                'MarkerEdgeColor','r','LineWidth',2,...
                'Tag','nodeMarker','PickableParts','all');
            
            % Make it clickable
            set(h, 'ButtonDownFcn', @(~,~)nodeClicked(i));
            nodeHandles(i) = h;
            
            % Draw smaller visible marker on top
            plot(ax,nodePositions(i,1),nodePositions(i,2),...
                'ro','MarkerSize',10,'MarkerFaceColor','r',...
                'LineWidth',2,'PickableParts','none');
            
            % Show node name or number
            label = nodeNames{i};
            if isempty(label)
                label = num2str(i);
            end
            text(ax,nodePositions(i,1)+10,nodePositions(i,2),...
                label,'Color','y','FontWeight','bold','FontSize',10,...
                'BackgroundColor',[0 0 0 0.5],'EdgeColor','none',...
                'PickableParts','none');
        end
        
        % Highlight selected node
        if ~isempty(selectedNode) && selectedNode <= size(nodePositions,1)
            plot(ax,nodePositions(selectedNode,1),nodePositions(selectedNode,2),...
                'co','MarkerSize',20,'LineWidth',4,'PickableParts','none');
        end
    end
    
    function saveGraph(~,~)
        if isempty(nodePositions); return; end
        
        % Handle case with no edges
        if isempty(edges)
            s = [];
            t = [];
            weights = [];
        else
            s = edges(:,1);
            t = edges(:,2);
            weights = edgeWeights;
        end
        
        G = graph(s,t,weights);
        G.Nodes.X = nodePositions(:,1);
        G.Nodes.Y = nodePositions(:,2);
        G.Nodes.Name = nodeNames';  % Save node names
        [file,path] = uiputfile('*.mat','Save Graph');
        if isequal(file,0); return; end
        save(fullfile(path,file),'G');
        fprintf('Graph saved\n');
    end
    
    function loadGraph(~,~)
        [file,path] = uigetfile('*.mat','Load Graph');
        if isequal(file,0); return; end
        data = load(fullfile(path,file));
        if ~isfield(data,'G')
            uialert(fig,'Invalid graph file','Load Error');
            return;
        end
        G = data.G;
        nodePositions = [G.Nodes.X G.Nodes.Y];
        
        % Handle edges - may be empty
        if numedges(G) > 0
            % Get edge endpoints - use findedge to get numeric indices
            edgeList = G.Edges.EndNodes;
            numEdges = size(edgeList, 1);
            edges = zeros(numEdges, 2);
            
            % Convert node names/indices to numeric indices
            for i = 1:numEdges
                % findnode returns the numeric index for a node
                edges(i,1) = findnode(G, edgeList(i,1));
                edges(i,2) = findnode(G, edgeList(i,2));
            end
            
            % Load weights if available
            if ismember('Weight', G.Edges.Properties.VariableNames)
                edgeWeights = G.Edges.Weight;
            else
                edgeWeights = ones(size(edges,1),1);
            end
        else
            edges = [];
            edgeWeights = [];
        end
        
        % Load node names if available
        numNodes = size(nodePositions,1);
        if ismember('Name', G.Nodes.Properties.VariableNames)
            % Extract names from table
            tempNames = G.Nodes.Name;
            
            % Convert to simple cell array of strings
            nodeNames = cell(1, numNodes);
            for i = 1:numNodes
                if iscell(tempNames)
                    % If it's a cell array
                    if iscell(tempNames{i})
                        nodeNames{i} = char(tempNames{i}{1});  % Nested cell
                    else
                        nodeNames{i} = char(tempNames{i});  % Regular cell
                    end
                else
                    % If it's a string/char array
                    nodeNames{i} = char(tempNames(i));
                end
            end
        else
            % Create default names
            nodeNames = cell(1, numNodes);
            for i = 1:numNodes
                nodeNames{i} = sprintf('Node %d', i);
            end
        end
        
        updateNodeList();
        updateEdgeList();
        updateStatus();
        redrawGraph();
        fprintf('Graph loaded with %d nodes and %d edges\n', size(nodePositions,1), size(edges,1));
    end
    
    function clearAll(~,~)
        nodePositions = [];
        nodeNames = {};
        edges = [];
        edgeWeights = [];
        selectedNode = [];
        imgData = [];
        imgHandle = [];
        nodeHandles = [];
        nodeListBox.Items = {};
        edgeListBox.Items = {};
        nodeNameField.Value = '';
        nodeNameField.Enable = 'off';
        edgeWeightField.Value = 1;
        edgeWeightField.Enable = 'off';
        cla(ax);
        updateStatus();
        fprintf('Cleared\n');
    end
end