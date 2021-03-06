%FTSE All Share components:
%https://uk.finance.yahoo.com/q/cp?s=%5EFTAS
%http://www.londonstockexchange.com/exchange/prices-and-markets/stocks/indices/summary/summary-indices-constituents.html?index=ASX
%
%S&P500 components:
%http://www.londonstockexchange.com/exchange/prices-and-markets/international-markets/indices/home/sp-500.html
%
%Other world indices:
%http://www.londonstockexchange.com/exchange/prices-and-markets/international-markets/indices/home.html

%Select stocks with at least 9 years of data available between January, 1 1990 and today
%Price data should be collected weekly on Fridays after market close. Data for stocks that were not traded during a particular week should be excluded.


%Download historical insider trading data (buy, sell)
buy_data=[];
page=1;
tokens=1;
while isempty(tokens)==0
    % Get current page url
    url_string = strcat('http://www.dataroma.com/m/m_activity.php?m=brk&typ=a&L=',int2str(page));
    % Read current page url
    str = urlread(url_string);
    % Regex to pull out the right classes 
    expr = '((?<=(<t(d|r) class="(stock|sell|buy|q_chg)">))(.*?)(?=(</td>)))|((?<=(<td>))(\d+\.\d+)(?=(</td>)))';
    tokens = regexp(str,expr,'tokens');
    % Squish it into a column
    tokens = vertcat(tokens{:});
    
    % Replace all the html formatting with spaces
    pat = '(<[^>]*>)|(&nbsp)';
    for i=1:size(tokens, 1)
        tokens(i, :)=regexprep(tokens(i, :), pat, '');
    end
    
    % Concat the data to the growing buffer
    buy_data=[buy_data; tokens];
    page=page+1 % end page
end

% create a vector of length 3
hist_buy_data=cell(1, 3);
count=size(hist_buy_data, 1);
% A ticker is GOOG. This is an array of company signs
tickers=[];
for i=1:size(buy_data, 1) % Loop through
    pat = 'Q(1|2|3|4)';
    % If this is a time period, set the var Qdate to it. 
    if regexp(buy_data{i}, pat)>0
        Qdate=buy_data{i};
    else
        % Set the next available entry to the date
        hist_buy_data{count, 1}=Qdate; 
        pat= '(.*?)(?=(\s-))'; % Matches name
        %pat2='Add|Reduce|Buy|Sell';
        pat2='Buy|Sell'; % Only tracking Buy and Sells
        pat3='\d+\.\d+'; % Tracks percent change to porfolio
        if regexp(buy_data{i}, pat)>0 % If name...
            % Change to porfolio = converted to array digit
            t_change=str2num(cell2mat(regexp(buy_data{i+3}, pat3, 'match')));
            if t_change>=0.1 % If the change percent > 0.1, then store company
                hist_buy_data{count, 2}=regexp(buy_data{i}, pat, 'match');
                tickers=[tickers, hist_buy_data{count, 2}];
            end
        elseif regexp(buy_data{i}, pat2)>0 % If this is buying / selling 
            if t_change>=0.1 % if the change > 0.1, keep it and store it in the hist.
                hist_buy_data{count, 3}=regexp(buy_data{i}, pat2, 'match');
                count=size(hist_buy_data, 1)+1; % Increase the count. 
                % If the company doesn't buy / sell, it'll get replaced.
            end
        end 
    end
end
hist_buy_data(count, :)=[];


%For each stock within the historical trading data download all historical
%fundamental data. % This is the interesting part.
tickers=unique(tickers); % Remove duplicates
% Create two empty structs
hist_fund_data=struct(); 
stocks=struct();
% The exchanges I'm interested in.
exchanges=[{'NYSE'}, {'NASDAQ'}, {'LSE'}, {'USOTC'}];

for i=1:size(tickers, 2)
    % Convert to string
    fund_name=char(tickers(i))
    
    % Initialize empty variables
    page=0;
    fund_data=cell(307,1); % Why 307? Probably knows the number of columns coming in.
    
    nr_table = 6;
    out_table=ones(1, 3);
    passer_var=0; % Indicates if we were in the loop or not
    
    while size(out_table, 2)>2 && page<200 % While we are less than 200 pages
        for j=1:size(exchanges, 2) % For each exchange 
            try
                exchange_name=char(exchanges(1, j)); % Convert name to char
                % Construct string. Start date = 0 since page = 0
                url_string = strcat('http://uk.advfn.com/p.php?pid=financials&btn=istart_date&mode=quarterly_reports&symbol=', exchange_name ,'%3A', fund_name, '&istart_date=', int2str(page))
                % Somehow picks out all the data! What is nr_table used for? 
                out_table  = getTableFromWeb_mod(url_string, nr_table);
                passer_var=1;
                break;
            catch
                sprintf('NO')
            end
        end
        
        if passer_var==0
            break;
        end
        
        size_ot=size(out_table, 1); % This should be 307.
        % This is the second column padded with zeros. If everything worked, there should be no padding. 
        new_data=[out_table(:, 2); num2cell(zeros(307-size_ot, 1))];
        
        % Add new_data to growing stack.
        fund_data=[fund_data, new_data];
        page=page+1
    end
    
    % Still in the loop for each ticker
    if passer_var==1 % If we managed to get data from uk website
        % Set the first column as the variable list
        fund_data(1:size_ot, 1)=out_table(:, 1);
        
        % If for some reason we've missed some attributes, fill the
        % remaining entries with blanks.
        if size_ot<307
            fund_data((size_ot+1):end, :)=[];
        end
        
        % Flip the matrix.
        fund_data=fund_data';

        expr='^[0-9]{4}';
        % The size of fund_data's 1st dimension should be 1. 
        for i=2:size(fund_data, 1)
            % Get's the year and applies a regex to pull it out.
            year=regexp(fund_data(i, 2), expr, 'match'); % year{1} pulls it out
            % Convert the year to Q# #### format
            fund_data(i, 1)=cellstr(sprintf('Q%s %s', fund_data{i, 5}, char(year{1})));
        end
        
        % Remove fundamental data in different format than the majority
        if size_ot==307
            % This is basically a hash. It hashes the ticker to the giant
            % piece of data we pulled.
            hist_fund_data.(fund_name)=fund_data;
        end
    end
    
    %Download historical fund data -- What is this?
    % 6 year total span
    start_date = '01012007'; % Jan 1st, 2007
    end_date = '31122012'; % Dec 31st, 2012
    try
        % Pulls stock information from CSV or something. 
        stocks.(fund_name) = hist_stock_data(start_date, end_date, fund_name);
    catch
        continue
    end
end

% We end with two giant structures - hist_fund_data, and stocks.
% hist_fund_data is composed of matrices itself consisting of features per
% ticker. 
